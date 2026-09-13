const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const sourcePath = path.resolve(__dirname, "../../modules/common/functions/EmailDetections.js");
const source = fs.readFileSync(sourcePath, "utf8");
const sandbox = {};
vm.runInNewContext(source + "\nthis.detectAll = detectAll;", sandbox, { filename: sourcePath });

function codes(body) {
    return JSON.parse(JSON.stringify(sandbox.detectAll(body).codes));
}

assert.deepStrictEqual(
    codes("Access your account. Your confirmation code is 123456."),
    ["123456"]
);

assert.deepStrictEqual(
    codes("<p>Use your verification code: <strong>AB12CD</strong></p>"),
    ["AB12CD"]
);

assert.deepStrictEqual(
    codes("Seu código de confirmação é: 987654"),
    ["987654"]
);

assert.deepStrictEqual(
    codes("Click here to access your account."),
    []
);

assert.deepStrictEqual(
    codes("Use 2468 to verify your login."),
    ["2468"]
);

assert.deepStrictEqual(
    codes("Use code: 123-456."),
    ["123-456"]
);

assert.deepStrictEqual(
    codes("<p>Seu&nbsp;código&nbsp;é&nbsp;<b>12&#51;456</b></p>"),
    ["123456"]
);

console.log("Email detection tests passed");
