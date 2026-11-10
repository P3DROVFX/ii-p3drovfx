#!/usr/bin/env python3
"""Where the eye goes in a picture, for the wallpaper framing's snap.

Prints one JSON object: {"x": 0..1, "y": 0..1, "kind": "face" | "detail"}
in the picture's own coordinates (0,0 top-left), or {} when there is no
answer. A face wins when one is found (the largest); otherwise the centre
of the spectral-residual saliency map - the part of the picture that
differs from what the rest of it predicts.
"""
import json
import os
import sys

os.environ["OPENCV_LOG_LEVEL"] = "SILENT"


def cascade_path():
    import cv2
    candidates = []
    data = getattr(cv2, "data", None)
    if data is not None:
        candidates.append(os.path.join(data.haarcascades, "haarcascade_frontalface_default.xml"))
    candidates += [
        "/usr/share/opencv4/haarcascades/haarcascade_frontalface_default.xml",
        "/usr/share/opencv/haarcascades/haarcascade_frontalface_default.xml",
    ]
    return next((path for path in candidates if os.path.isfile(path)), None)


def find_face(gray):
    import cv2
    path = cascade_path()
    if path is None:
        return None
    cascade = cv2.CascadeClassifier(path)
    if cascade.empty():
        return None
    h, w = gray.shape
    side = max(24, int(min(w, h) * 0.06))
    faces = cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=6, minSize=(side, side))
    if len(faces) == 0:
        return None
    x, y, fw, fh = max(faces, key=lambda f: f[2] * f[3])
    return (x + fw / 2) / w, (y + fh / 2) / h


def find_detail(gray):
    import cv2
    import numpy as np
    small = cv2.resize(gray, (64, 64), interpolation=cv2.INTER_AREA).astype(np.float64)
    spectrum = np.fft.fft2(small)
    log_amplitude = np.log(np.abs(spectrum) + 1e-9)
    residual = log_amplitude - cv2.blur(log_amplitude, (3, 3))
    saliency = np.abs(np.fft.ifft2(np.exp(residual + 1j * np.angle(spectrum)))) ** 2
    saliency = cv2.GaussianBlur(saliency, (9, 9), 2.5)
    # Keep the most salient tenth so a busy background does not average the
    # answer back to the middle.
    cut = np.percentile(saliency, 90)
    weights = np.where(saliency >= cut, saliency, 0)
    total = weights.sum()
    if total <= 0:
        return None
    ys, xs = np.mgrid[0:64, 0:64]
    return float((weights * (xs + 0.5)).sum() / total / 64), float((weights * (ys + 0.5)).sum() / total / 64)


def main():
    if len(sys.argv) < 2:
        print("{}")
        return
    try:
        import cv2
        image = cv2.imread(sys.argv[1], cv2.IMREAD_GRAYSCALE)
        if image is None:
            print("{}")
            return
        h, w = image.shape
        scale = 640 / max(w, h)
        if scale < 1:
            image = cv2.resize(image, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)
        face = find_face(image)
        if face is not None:
            print(json.dumps({"x": round(face[0], 4), "y": round(face[1], 4), "kind": "face"}))
            return
        detail = find_detail(image)
        if detail is not None:
            print(json.dumps({"x": round(detail[0], 4), "y": round(detail[1], 4), "kind": "detail"}))
            return
    except Exception:
        pass
    print("{}")


if __name__ == "__main__":
    main()
