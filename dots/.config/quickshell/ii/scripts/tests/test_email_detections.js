const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const sourcePath = path.resolve(__dirname, "../../modules/common/functions/EmailDetections.js");
const source = fs.readFileSync(sourcePath, "utf8");
const sandbox = {};
vm.runInNewContext(source + "\nthis.detectAll = detectAll;", sandbox, { filename: sourcePath });

function codes(body, subject) {
    return JSON.parse(JSON.stringify(sandbox.detectAll(body, subject).codes));
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
    ["123456"]
);

assert.deepStrictEqual(
    codes("<p>Seu&nbsp;código&nbsp;é&nbsp;<b>12&#51;456</b></p>"),
    ["123456"]
);

// Real-world phrasings: the label is not glued to the code.
const found = [
    ["G-482913 is your Google verification code.", "482913"],
    ["<p>Enter the following code to sign in:</p><h1>582014</h1><p>This code expires in 10 minutes.</p>", "582014"],
    ["<p>Use o código abaixo para acessar sua conta:</p><div>481920</div>", "481920"],
    ["<p>Para concluir o login, insira este código:</p><p><b>7 3 9 2 0 4</b></p>", "739204"],
    ["<p>Your verification code:</p><table><tr><td>4</td><td>8</td><td>2</td><td>9</td><td>1</td><td>3</td></tr></table>", "482913"],
    ["<p>Here is your one-time passcode (OTP):</p><p>3049</p>", "3049"],
    ["<p>Seu código de verificação do Nubank é <b>829</b></p>", "829"],
    ["<p>Please use this code to reset your password</p><p>91827</p>", "91827"],
    ["<p>Copie e cole este código de confirmação no aplicativo:</p><p>XK2-9PL</p>", "XK2-9PL"],
    ["<p>Your login code for Claude is</p><h2>384-219</h2>", "384219"],
    ["<p>482913</p><p>Use this code to verify your account.</p>", "482913"],
    ["<td>Steam Guard code</td></tr><tr><td>F4K9X</td>", "F4K9X"],
    ["Your Instagram code is 492 018. Don't share it.", "492018"],
    ["<p>Your Netflix sign-in code</p><p>Enter this code to sign in</p><p>4729</p>", "4729"],
    ["<p>We received a request to sign in. Enter the code below.</p><center><b> 918 273 </b></center><p>This code will expire in 15 minutes.</p><p>&copy; 2026 Example Inc. 123 Market St, San Francisco CA 94105</p>", "918273"],
];
for (const [body, code] of found)
    assert.deepStrictEqual(codes(body), [code], body);

assert.deepStrictEqual(codes("<p>Sign in to continue.</p>", "Your Microsoft code is 774102"), ["774102"]);

// Numbers that only sit near a label are not codes.
const none = [
    "<p>Pedido #12345 confirmado. Total R$ 2025,00. Ligue 1234-5678.</p>",
    "<p>Meeting on 2026-11-04 at 10:30, room 1234. Order 99821 shipped.</p>",
    "<p>Your password was changed on November 4, 2026.</p>",
    "<p>Hi Pedro, your Uber receipt. Trip on Nov 4, 2026. Total: $23.40</p>",
    "<p>Read our new post about code review in 2026 with 1500 examples.</p>",
    "<p>Você recebeu um Pix de R$ 150,00. Agência 0001, conta 123456-7.</p>",
    "<p>Ligue para (11) 98765-4321 para confirmar seu código.</p>",
];
for (const body of none)
    assert.deepStrictEqual(codes(body), [], body);

console.log("Email detection tests passed");
