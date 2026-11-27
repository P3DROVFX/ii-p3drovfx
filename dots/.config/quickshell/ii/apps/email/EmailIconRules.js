// Email icon classification rules
const rules = [
    // High Priority Brands
    { i: "google", p: [/google/i, /gmail/i, /android/i, /firebase/i, /drive\.google/i, /youtube/i] },
    { i: "github", p: [/github/i] },
    { i: "gitlab", p: [/gitlab/i] },
    { i: "discord", p: [/discord/i] },
    { i: "microsoft", p: [/microsoft/i, /outlook/i, /office 365/i, /windows/i, /azure/i] },
    { i: "apple", p: [/apple/i, /icloud/i, /app store/i] },
    { i: "amazon", p: [/amazon/i, /prime video/i, /\baws\b/i] },
    { i: "facebook", p: [/facebook/i] },
    { i: "twitter", p: [/twitter/i, /\bx\b/i] },
    { i: "instagram", p: [/instagram/i] },
    { i: "linkedin", p: [/linkedin/i] },
    { i: "spotify", p: [/spotify/i] },
    { i: "steam", p: [/steam/i] },
    { i: "twitch", p: [/twitch/i] },
    { i: "paypal", p: [/paypal/i] },

    // Education
    { i: "udemy", p: [/udemy/i] },
    { i: "coursera", p: [/coursera/i] },
    { i: "duolingo", p: [/duolingo/i] },
    { i: "edx", p: [/edx/i] },
    { i: "pluralsight", p: [/pluralsight/i] },

    // Marketplaces
    { i: "aliexpress", p: [/aliexpress/i] },
    { i: "mercadolivre", p: [/mercado livre/i, /mercadolivre/i] },
    { i: "shopee", p: [/shopee/i] },
    { i: "ebay", p: [/ebay/i] },
    { i: "etsy", p: [/etsy/i] },
    { i: "wish", p: [/wish\b/i] },
    { i: "temu", p: [/temu/i] },

    // Social/Video
    { i: "youtube", p: [/youtube/i] },
    { i: "tiktok", p: [/tiktok/i] },
    { i: "snapchat", p: [/snapchat/i] },
    { i: "pinterest", p: [/pinterest/i] },

    // Finance
    { i: "nubank", p: [/nubank/i] },
    { i: "inter", p: [/banco inter/i, /\binter\b/i] },
    { i: "binance", p: [/binance/i] },
    { i: "coinbase", p: [/coinbase/i] },

    // Dev Tools
    { i: "python", p: [/python/i, /django/i, /flask/i, /pypi/i] },
    { i: "javascript", p: [/javascript/i, /node\.js/i, /\bjs\b/i] },
    { i: "typescript", p: [/typescript/i, /\bts\b/i] },
    { i: "rust", p: [/\brust\b/i, /cargo/i, /crates\.io/i] },
    { i: "docker", p: [/docker/i, /container/i] },
    { i: "kubernetes", p: [/kubernetes/i, /k8s/i] },
    { i: "vercel", p: [/vercel/i] },

    // General Categories
    { i: "local_shipping", p: [/tracking/i, /rastreio/i, /entregue/i, /shipped/i, /delivery/i, /correios/i, /shipment/i] },
    { i: "receipt_long", p: [/invoice/i, /fatura/i, /compra/i, /purchase/i, /pagamento/i, /recibo/i, /nota fiscal/i, /billing/i] },
    { i: "security", p: [/login/i, /senha/i, /password/i, /2fa/i, /verify/i, /security/i, /segurança/i, /suspicious/i] },
    { i: "campaign", p: [/unsubscribe/i, /newsletter/i, /mailing/i, /boletim/i, /informativo/i, /news/i, /digest/i] },
    { i: "event", p: [/invite/i, /meeting/i, /event/i, /reunião/i, /agendado/i, /calendar/i, /convite/i, /appointment/i] },
    { i: "school", p: [/course/i, /certificado/i, /learn/i, /aula/i, /escola/i, /universidade/i, /education/i, /certificate/i] },
    { i: "restaurant", p: [/ifood/i, /uber eats/i, /rappi/i, /comida/i, /restaurante/i, /food/i] },
    { i: "account_balance", p: [/extrato/i, /saldo/i, /transferência/i, /pix/i, /bank/i, /banco/i, /statement/i] },
    { i: "sell", p: [/promoção/i, /desconto/i, /discount/i, /sale/i, /oferta/i, /cupom/i, /coupon/i] }
];

function classify(subject, sender, snippet) {
    const text = (subject + " " + sender + " " + snippet).toLowerCase();
    for (let i = 0; i < rules.length; i++) {
        const rule = rules[i];
        for (let j = 0; j < rule.p.length; j++) {
            if (rule.p[j].test(text)) return rule.i;
        }
    }
    return "person";
}
