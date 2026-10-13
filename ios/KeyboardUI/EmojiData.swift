/// The emoji page's emoji, by category, in the order Apple's keyboard shows
/// them. Only emoji up to version 14, which iOS 16 draws; newer ones would
/// show as empty boxes there.
enum EmojiData {
    struct Category: Identifiable {
        let id: String
        let symbol: String
        let emoji: [String]
    }

    static let categories: [Category] = [
        Category(id: "Smileys and people", symbol: "face.smiling", emoji: split("""
            😀😃😄😁😆🥹😅😂🤣🥲☺️😊😇🙂🙃😉😌😍🥰😘😗😙😚😋😛😝😜🤪🤨🧐🤓😎🥸🤩🥳😏😒😞😔😟😕🙁☹️😣😖😫😩🥺😢😭😮‍💨😤😠😡🤬🤯😳🥵🥶😱😨😰😥😓🫣🤗🫡🤔🫢🤭🤫🤥😶😶‍🌫️😐😑😬🫠🙄😯😦😧😮😲🥱😴🤤😪😵😵‍💫🫥🤐🥴🤢🤮🤧😷🤒🤕🤑🤠😈👿👹👺🤡💩👻💀☠️👽👾🤖🎃😺😸😹😻😼😽🙀😿😾\
            👋🤚🖐️✋🖖🫱🫲🫳🫴👌🤌🤏✌️🤞🫰🤟🤘🤙👈👉👆🖕👇☝️🫵👍👎✊👊🤛🤜👏🙌🫶👐🤲🤝🙏✍️💅🤳💪🦾🦵🦶👂👃🧠🫀🫁🦷🦴👀👁️👅👄🫦\
            👶🧒👦👧🧑👱👨🧔👩🧓👴👵🙍🙎🙅🙆💁🙋🧏🙇🤦🤷👮🕵️💂🥷👷🫅🤴👸👳👲🧕🤵👰🤰🫄🤱👼🎅🤶🦸🦹🧙🧚🧛🧜🧝🧞🧟🧌💆💇🚶🧍🧎🏃💃🕺👯🧖🧗🤺🏇⛷️🏂🏌️🏄🚣🏊⛹️🏋️🚴🚵🤸🤼🤽🤾🤹🧘🛀🛌👭👫👬💏💑👪🗣️👤👥🫂👣\
            ❤️🧡💛💚💙💜🖤🤍🤎💔❤️‍🔥❤️‍🩹❣️💕💞💓💗💖💘💝💟💋💌
            """)),
        Category(id: "Animals and nature", symbol: "pawprint", emoji: split("""
            🐶🐱🐭🐹🐰🦊🐻🐼🐻‍❄️🐨🐯🦁🐮🐷🐽🐸🐵🙈🙉🙊🐒🐔🐧🐦🐤🐣🐥🦆🦅🦉🦇🐺🐗🐴🦄🐝🪱🐛🦋🐌🐞🐜🪰🪲🪳🦟🦗🕷️🦂🐢🐍🦎🦖🦕🐙🦑🦐🦞🦀🐡🐠🐟🐬🐳🐋🦈🦭🐊🐅🐆🦓🦍🦧🦣🐘🦛🦏🐪🐫🦒🦘🦬🐃🐂🐄🐎🐖🐏🐑🦙🐐🦌🐕🐩🦮🐈🐈‍⬛🪶🐓🦃🦤🦚🦜🦢🦩🕊️🐇🦝🦨🦡🦫🦦🦥🐁🐀🐿️🦔🐾🐉🐲\
            🌵🎄🌲🌳🌴🪵🌱🌿☘️🍀🎍🪴🎋🍃🍂🍁🍄🐚🪸🪨🌾💐🌷🌹🥀🪷🌺🌸🌼🌻🌞🌝🌛🌜🌚🌕🌖🌗🌘🌑🌒🌓🌔🌙🌎🌍🌏🪐💫⭐️🌟✨⚡️☄️💥🔥🌪️🌈☀️🌤️⛅️🌥️☁️🌦️🌧️⛈️🌩️🌨️❄️☃️⛄️🌬️💨💧💦🫧☔️☂️🌊
            """)),
        Category(id: "Food and drink", symbol: "fork.knife", emoji: split("""
            🍏🍎🍐🍊🍋🍌🍉🍇🍓🫐🍈🍒🍑🥭🍍🥥🥝🍅🍆🥑🥦🥬🥒🌶️🫑🌽🥕🫒🧄🧅🥔🍠🫘🥐🥯🍞🥖🥨🧀🥚🍳🧈🥞🧇🥓🥩🍗🍖🌭🍔🍟🍕🫓🥪🥙🧆🌮🌯🫔🥗🥘🫕🥫🍝🍜🍲🍛🍣🍱🥟🦪🍤🍙🍚🍘🍥🥠🥮🍢🍡🍧🍨🍦🥧🧁🍰🎂🍮🍭🍬🍫🍿🍩🍪🌰🥜🍯🥛🍼🫖☕️🍵🧃🥤🧋🍶🍺🍻🥂🍷🫗🥃🍸🍹🧉🍾🧊🥄🍴🍽️🥣🥡🥢🧂
            """)),
        Category(id: "Activity", symbol: "soccerball", emoji: split("""
            ⚽️🏀🏈⚾️🥎🎾🏐🏉🥏🎱🪀🏓🏸🏒🏑🥍🏏🪃🥅⛳️🪁🏹🎣🤿🥊🥋🎽🛹🛼🛷⛸️🥌🎿🪂🏆🥇🥈🥉🏅🎖️🏵️🎗️🎫🎟️🎪🎭🩰🎨🎬🎤🎧🎼🎹🥁🪘🎷🎺🪗🎸🪕🎻🎲♟️🎯🎳🎮🎰🧩
            """)),
        Category(id: "Travel and places", symbol: "car", emoji: split("""
            🚗🚕🚙🚌🚎🏎️🚓🚑🚒🚐🛻🚚🚛🚜🦯🦽🦼🛴🚲🛵🏍️🛺🚨🚔🚍🚘🚖🛞🚡🚠🚟🚃🚋🚞🚝🚄🚅🚈🚂🚆🚇🚊🚉✈️🛫🛬🛩️💺🛰️🚀🛸🚁🛶⛵️🚤🛥️🛳️⛴️🚢🛟⚓️🪝⛽️🚧🚦🚥🚏🗺️🗿🗽🗼🏰🏯🏟️🎡🎢🛝🎠⛲️⛱️🏖️🏝️🏜️🌋⛰️🏔️🗻🏕️⛺️🛖🏠🏡🏘️🏚️🏗️🏭🏢🏬🏣🏤🏥🏦🏨🏪🏫🏩💒🏛️⛪️🕌🕍🛕🕋⛩️🛤️🛣️🗾🎑🏞️🌅🌄🌠🎇🎆🌇🌆🏙️🌃🌌🌉🌁
            """)),
        Category(id: "Objects", symbol: "lightbulb", emoji: split("""
            ⌚️📱📲💻⌨️🖥️🖨️🖱️🖲️🕹️🗜️💽💾💿📀📼📷📸📹🎥📽️🎞️📞☎️📟📠📺📻🎙️🎚️🎛️🧭⏱️⏲️⏰🕰️⌛️⏳📡🔋🪫🔌💡🔦🕯️🪔🧯🛢️💸💵💴💶💷🪙💰💳💎⚖️🪜🧰🪛🔧🔨⚒️🛠️⛏️🪚🔩⚙️🪤🧱⛓️🧲🔫💣🧨🪓🔪🗡️⚔️🛡️🚬⚰️🪦⚱️🏺🔮📿🧿🪬💈⚗️🔭🔬🕳️🩻🩹🩺💊💉🩸🧬🦠🧫🧪🌡️🧹🪠🧺🧻🚽🚰🚿🛁🧼🪥🪒🧽🪣🧴🛎️🔑🗝️🚪🪑🛋️🛏️🧸🪆🖼️🪞🪟🛍️🛒🎁🎈🎏🎀🪄🪅🎊🎉🎎🏮🎐🧧✉️📩📨📧📥📤📦🏷️🪧📪📫📬📭📮📯📜📃📄📑🧾📊📈📉🗒️🗓️📆📅🗑️📇🗃️🗳️🗄️📋📁📂🗂️🗞️📰📓📔📒📕📗📘📙📚📖🔖🧷🔗📎🖇️📐📏🧮📌📍✂️🖊️🖋️✒️🖌️🖍️📝✏️🔍🔎🔏🔐🔒🔓
            """)),
        Category(id: "Symbols", symbol: "heart", emoji: split("""
            ☮️✝️☪️🕉️☸️✡️🔯🕎☯️☦️🛐⛎♈️♉️♊️♋️♌️♍️♎️♏️♐️♑️♒️♓️🆔⚛️🉑☢️☣️📴📳🈶🈚️🈸🈺🈷️✴️🆚💮🉐㊙️㊗️🈴🈵🈹🈲🅰️🅱️🆎🆑🅾️🆘❌⭕️🛑⛔️📛🚫💯💢♨️🚷🚯🚳🚱🔞📵🚭❗️❕❓❔‼️⁉️🔅🔆〽️⚠️🚸🔱⚜️🔰♻️✅🈯️💹❇️✳️❎🌐💠Ⓜ️🌀💤🏧🚾♿️🅿️🛗🈳🈂️🛂🛃🛄🛅🚹🚺🚼⚧️🚻🚮🎦📶🈁🔣ℹ️🔤🔡🔠🆖🆗🆙🆒🆕🆓0️⃣1️⃣2️⃣3️⃣4️⃣5️⃣6️⃣7️⃣8️⃣9️⃣🔟🔢#️⃣*️⃣⏏️▶️⏸️⏯️⏹️⏺️⏭️⏮️⏩️⏪️⏫️⏬️◀️🔼🔽➡️⬅️⬆️⬇️↗️↘️↙️↖️↕️↔️↪️↩️⤴️⤵️🔀🔁🔂🔄🔃🎵🎶➕➖➗✖️🟰♾️💲💱™️©️®️〰️➰➿🔚🔙🔛🔝🔜✔️☑️🔘🔴🟠🟡🟢🔵🟣⚫️⚪️🟤🔺🔻🔸🔹🔶🔷🔳🔲▪️▫️◾️◽️◼️◻️🟥🟧🟨🟩🟦🟪⬛️⬜️🟫🔈🔇🔉🔊🔔🔕📣📢💬💭🗯️♠️♣️♥️♦️🃏🎴🀄️🕐🕑🕒🕓🕔🕕🕖🕗🕘🕙🕚🕛
            """)),
        Category(id: "Flags", symbol: "flag", emoji: split("🏁🚩🎌🏴🏳️🏳️‍🌈🏳️‍⚧️🏴‍☠️") + countryFlags),
    ]

    private static func split(_ text: String) -> [String] {
        text.filter { !$0.isWhitespace }.map(String.init)
    }

    /// A flag for each country, made from its two-letter code, in order.
    private static let countryFlags: [String] = """
        AF AX AL DZ AS AD AO AI AQ AG AR AM AW AU AT AZ BS BH BD BB BY BE BZ BJ BM BT BO BA BW BR \
        IO VG BN BG BF BI KH CM CA IC CV BQ KY CF TD CL CN CX CC CO KM CG CD CK CR CI HR CU CW CY \
        CZ DK DJ DM DO EC EG SV GQ ER EE SZ ET EU FK FO FJ FI FR GF PF TF GA GM GE DE GH GI GR GL \
        GD GP GU GT GG GN GW GY HT HN HK HU IS IN ID IR IQ IE IM IL IT JM JP JE JO KZ KE KI XK KW \
        KG LA LV LB LS LR LY LI LT LU MO MG MW MY MV ML MT MH MQ MR MU YT MX FM MD MC MN ME MS MA \
        MZ MM NA NR NP NL NC NZ NI NE NG NU NF KP MK MP NO OM PK PW PS PA PG PY PE PH PN PL PT PR \
        QA RE RO RU RW WS SM ST SA SN RS SC SL SG SX SK SI GS SB SO ZA KR SS ES LK BL SH KN LC PM \
        VC SD SR SE CH SY TW TJ TZ TH TL TG TK TO TT TN TR TM TC TV UG UA AE GB US VI UY UZ VU VA \
        VE VN WF EH YE ZM ZW
        """.split(separator: " ").map { code in
            String(String.UnicodeScalarView(code.unicodeScalars.compactMap { Unicode.Scalar(0x1F1A5 + $0.value) }))
        }
}
