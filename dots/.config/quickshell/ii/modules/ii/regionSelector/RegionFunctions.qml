pragma Singleton
import Quickshell

Singleton {
    id: root

    function intersectionOverUnion(regionA, regionB) {
        // region: { at: [x, y], size: [w, h] }
        const ax1 = regionA.at[0], ay1 = regionA.at[1];
        const ax2 = ax1 + regionA.size[0], ay2 = ay1 + regionA.size[1];
        const bx1 = regionB.at[0], by1 = regionB.at[1];
        const bx2 = bx1 + regionB.size[0], by2 = by1 + regionB.size[1];

        const interX1 = Math.max(ax1, bx1);
        const interY1 = Math.max(ay1, by1);
        const interX2 = Math.min(ax2, bx2);
        const interY2 = Math.min(ay2, by2);

        const interArea = Math.max(0, interX2 - interX1) * Math.max(0, interY2 - interY1);
        const areaA = (ax2 - ax1) * (ay2 - ay1);
        const areaB = (bx2 - bx1) * (by2 - by1);
        const unionArea = areaA + areaB - interArea;

        return unionArea > 0 ? interArea / unionArea : 0;
    }

    function filterOverlappingImageRegions(regions) {
        let keep = [];
        let removed = new Set();
        for (let i = 0; i < regions.length; ++i) {
            if (removed.has(i)) continue;
            let regionA = regions[i];
            for (let j = i + 1; j < regions.length; ++j) {
                if (removed.has(j)) continue;
                let regionB = regions[j];
                if (intersectionOverUnion(regionA, regionB) > 0) {
                    // Compare areas
                    let areaA = regionA.size[0] * regionA.size[1];
                    let areaB = regionB.size[0] * regionB.size[1];
                    if (areaA <= areaB) {
                        removed.add(j);
                    } else {
                        removed.add(i);
                    }
                }
            }
        }
        for (let i = 0; i < regions.length; ++i) {
            if (!removed.has(i)) keep.push(regions[i]);
        }
        return keep;
    }

    // Fraction of `region` covered by `cover`.
    function coverage(region, cover) {
        const x1 = Math.max(region.at[0], cover.at[0]);
        const y1 = Math.max(region.at[1], cover.at[1]);
        const x2 = Math.min(region.at[0] + region.size[0], cover.at[0] + cover.size[0]);
        const y2 = Math.min(region.at[1] + region.size[1], cover.at[1] + cover.size[1]);
        const area = region.size[0] * region.size[1];
        return area > 0 ? Math.max(0, x2 - x1) * Math.max(0, y2 - y1) / area : 0;
    }

    // Drops only windows hidden behind a layer. Touching one is not enough:
    // a thin shell strip along the top used to remove every tiled window,
    // and layers already win the hover by being checked first.
    function filterWindowRegionsByLayers(windowRegions, layerRegions) {
        return windowRegions.filter(windowRegion => {
            for (let i = 0; i < layerRegions.length; ++i) {
                if (coverage(windowRegion, layerRegions[i]) > 0.9)
                    return false;
            }
            return true;
        });
    }

    function filterImageRegions(regions, windowRegions, threshold = 0.1) {
        // Remove image regions that overlap too much with any window region
        let filtered = regions.filter(region => {
            for (let i = 0; i < windowRegions.length; ++i) {
                if (intersectionOverUnion(region, windowRegions[i]) > threshold)
                    return false;
            }
            return true;
        });
        // Remove overlapping image regions, keep only the smaller one
        return filterOverlappingImageRegions(filtered);
    }
}
