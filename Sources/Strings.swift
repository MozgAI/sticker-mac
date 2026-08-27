import SwiftUI

/// Язык интерфейса. По умолчанию — английский, кроме русских и украинских систем.
enum Lang: String, CaseIterable, Identifiable {
    case en, ru, uk
    var id: String { rawValue }
    var flag: String {
        switch self {
        case .en: return "🇬🇧"
        case .ru: return "🇷🇺"
        case .uk: return "🇺🇦"
        }
    }
}

@MainActor
final class L10n: ObservableObject {
    static let shared = L10n()
    private let key = "uiLanguage"

    @Published var lang: Lang {
        didSet { UserDefaults.standard.set(lang.rawValue, forKey: key) }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "uiLanguage"),
           let l = Lang(rawValue: saved) {
            lang = l
        } else {
            let sys = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "en"
            lang = sys == "ru" ? .ru : (sys == "uk" ? .uk : .en)
        }
    }

    func callAsFunction(_ key: String) -> String { t(key) }

    /// Перевод без привязки к главному потоку — для описаний ошибок и фоновых мест.
    nonisolated static func tr(_ key: String) -> String {
        let raw = UserDefaults.standard.string(forKey: "uiLanguage")
            ?? (Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "en")
        let lang = Lang(rawValue: String(raw)) ?? .en
        guard let row = translations[key] else { return key }
        switch lang {
        case .en: return row.0
        case .ru: return row.1
        case .uk: return row.2
        }
    }

    func t(_ key: String) -> String {
        guard let row = translations[key] else { return key }
        switch lang {
        case .en: return row.0
        case .ru: return row.1
        case .uk: return row.2
        }
    }

}

/// (english, русский, українська)
let translations: [String: (String, String, String)] = [
        "print":        ("PRINT", "ПЕЧАТЬ", "ДРУК"),
        "printing":     ("Printing…", "Печатаю…", "Друкую…"),
        "printingN":    ("Printing %@ of %@…", "Печатаю %@ из %@…", "Друкую %@ з %@…"),
        "copies":       ("Copies", "Копий", "Копій"),
        "testShape":    ("Test outline", "Пробный контур", "Пробний контур"),
        "testHelp":     ("Prints an empty outline to check it lands on the die-cut",
                         "Печатает пустой контур — проверить попадание в вырубку",
                         "Друкує порожній контур — перевірити влучання у вирубку"),
        "savePNG":      ("Save PNG", "Сохранить PNG", "Зберегти PNG"),
        "sectionPrint": ("PRINT", "ПЕЧАТЬ", "ДРУК"),
        "ready":        ("ready", "готов", "готовий"),

        "sectionImage": ("IMAGE", "КАРТИНКА", "ЗОБРАЖЕННЯ"),
        "open":         ("Open…", "Открыть…", "Відкрити…"),
        "center":       ("Center", "По центру", "По центру"),
        "scale":        ("Scale", "Масштаб", "Масштаб"),

        "sectionShape": ("LABEL SHAPE", "ФОРМА НАКЛЕЙКИ", "ФОРМА НАКЛЕЙКИ"),
        "circle":       ("Circle", "Круг", "Коло"),
        "rect":         ("Rectangle", "Прямоугольник", "Прямокутник"),
        "diameter":     ("Artwork diameter", "Диаметр рисунка", "Діаметр малюнка"),
        "artWidth":     ("Artwork width", "Ширина рисунка", "Ширина малюнка"),
        "artHeight":    ("Artwork height", "Высота рисунка", "Висота малюнка"),
        "corner":       ("Corner radius", "Скругление углов", "Заокруглення кутів"),
        "shapeHint":    ("How big to print. Must fit inside the label.",
                         "Насколько крупно печатать. Должно влезать в наклейку.",
                         "Наскільки великим друкувати. Має вміщатися в наклейку."),

        "sectionLabel": ("LABEL SIZE", "РАЗМЕР НАКЛЕЙКИ", "РОЗМІР НАКЛЕЙКИ"),
        "feed":         ("Feed length", "Шаг подачи", "Крок подачі"),
        "labelWidth":   ("Label width", "Ширина наклейки", "Ширина наклейки"),
        "feedHint":     ("How much tape to advance — one label including the gap. Dashed outline in the preview.",
                         "Сколько ленты протянуть — высота одной наклейки с зазором. Белый пунктир в превью.",
                         "Скільки стрічки протягнути — висота однієї наклейки із зазором. Пунктир у превʼю."),

        "sectionAlign": ("ALIGNMENT", "ВЫРАВНИВАНИЕ", "ВИРІВНЮВАННЯ"),
        "alignHint":    ("If the print creeps off the die-cut, nudge it here. Top number — sideways, bottom — along the tape.",
                         "Если печать съезжает с вырубленного круга — двигай стрелками. Сверху — сдвиг вбок, снизу — по ленте.",
                         "Якщо друк з’їжджає з вирубки — рухай стрілками. Зверху — вбік, знизу — по стрічці."),
        "alignFlipped": ("Arrows move the print the way you see it on the flipped preview.",
                         "Стрелки двигают так, как ты видишь на перевёрнутом превью.",
                         "Стрілки рухають так, як ти бачиш на перевернутому превʼю."),
        "resetHelp":    ("Click to reset", "Нажми, чтобы обнулить", "Натисни, щоб обнулити"),

        "sectionOrient":("ORIENTATION ON TAPE", "ОРИЕНТАЦИЯ НА ЛЕНТЕ", "ОРІЄНТАЦІЯ НА СТРІЧЦІ"),
        "asIs":         ("As is", "Как есть", "Як є"),
        "mirror":       ("Mirror", "Зеркало", "Дзеркало"),
        "both":         ("Both", "Оба", "Обидва"),
        "orientHint":   ("If it came out mirrored or upside down, switch here. The preview never changes: it always shows the label as it lands in your hand.",
                         "Если вышло зеркально или вверх ногами — переключи здесь. Превью не меняется: там всегда как ляжет в руку.",
                         "Якщо вийшло дзеркально або догори дриґом — перемкни тут. Превʼю не змінюється: там завжди як ляже в руку."),
        "quality":      ("Quality", "Качество", "Якість"),
        "qMax":         ("Best", "Максимум", "Максимум"),
        "qMid":         ("Medium", "Средне", "Середнє"),
        "qFast":        ("Fast", "Быстро", "Швидко"),

        "sectionHow":   ("HOW TO PRINT", "КАК ПЕЧАТАТЬ", "ЯК ДРУКУВАТИ"),
        "artwork":      ("Artwork", "Рисунок", "Малюнок"),
        "photo":        ("Photo", "Фото", "Фото"),
        "artworkHint":  ("Pure black and white — for monograms, lettering and logos.",
                         "Чисто чёрное и белое — для вензелей, надписей и лого.",
                         "Чисто чорне й біле — для вензелів, написів і лого."),
        "photoHint":    ("Halftones rendered as dots — for photographs and gradients.",
                         "Полутона точками — для фотографий и градиентов.",
                         "Півтони крапками — для фотографій і градієнтів."),
        "threshold":    ("Black threshold", "Порог чёрного", "Поріг чорного"),
        "thresholdHint":("Lower — only the darkest parts. Higher — thin lines survive.",
                         "Ниже — только самое тёмное. Выше — тонкие линии не пропадут.",
                         "Нижче — лише найтемніше. Вище — тонкі лінії не зникнуть."),
        "cleanBG":      ("Background cleanup", "Чистка фона", "Чищення фону"),
        "cleanHint":    ("Kills JPEG speckle on areas that only look white.",
                         "Убирает крапинки на белом от сжатия JPEG.",
                         "Прибирає цятки на білому від стиснення JPEG."),
        "negative":     ("Negative", "Негатив", "Негатив"),
        "showPrinted":  ("Show as printed", "Показывать как напечатается", "Показувати як надрукується"),
        "brightness":   ("Brightness", "Яркость", "Яскравість"),
        "contrast":     ("Contrast", "Контраст", "Контраст"),
        "density":      ("Heat", "Нагрев", "Нагрів"),

        "sectionPrinter":("PRINTER", "ПРИНТЕР", "ПРИНТЕР"),
        "namePlaceholder":("part of the printer name", "часть имени принтера", "частина назви принтера"),
        "scan":         ("Scan", "Искать", "Шукати"),
        "filterHint":   ("Empty — looks for any label printer. Type part of your printer's name if several are around.",
                         "Пусто — ищу любой принтер этикеток. Впиши кусок имени своего, если рядом несколько.",
                         "Порожньо — шукаю будь-який принтер етикеток. Впиши частину назви свого, якщо поруч кілька."),
        "pin":          ("Remember this printer", "Запомнить этот принтер", "Запамʼятати цей принтер"),
        "pinned":       ("Pinned", "Закреплён", "Закріплено"),
        "forget":       ("Forget", "Забыть", "Забути"),
        "disconnect":   ("Disconnect", "Отключить", "Відключити"),
        "devicesHint":  ("In range — tap your printer:", "Что в эфире — нажми свой принтер:", "Що в ефірі — натисни свій принтер:"),

        "flipPreview":  ("Flip preview", "Перевернуть превью", "Перевернути превʼю"),
        "flipOn":       ("as it comes out of the printer", "вид как из принтера", "вигляд як з принтера"),
        "flipHelp":     ("Show it the way the label leaves the printer",
                         "Показать так, как наклейка выезжает из принтера",
                         "Показати так, як наклейка виїжджає з принтера"),
        "dropHere":     ("Drop an image here", "Перетащи сюда картинку", "Перетягни сюди зображення"),
        "dropHint":     ("the pink area is cut off, the shape is printed",
                         "розовое обрежется, в форме — напечатается",
                         "рожеве обріжеться, у формі — надрукується"),
        "noFile":       ("No file selected", "Файл не выбран", "Файл не вибрано"),
        "dragToMove":   ("drag to move", "тяни мышкой, чтобы двигать", "тягни мишкою, щоб рухати"),
        "language":     ("Language", "Язык", "Мова"),

        "errorTitle":   ("Something went wrong", "Не получилось", "Не вийшло"),
        "errorOK":      ("OK", "Ясно", "Ясно"),
        "cantRead":     ("Cannot read this file", "Не читается файл", "Не читається файл"),

        "stStarting":   ("Turning Bluetooth on…", "Включаю Bluetooth…", "Вмикаю Bluetooth…"),
        "stSearching":  ("Looking for a printer…", "Ищу принтер…", "Шукаю принтер…"),
        "stFound":      ("Printers found: %@", "Нашла принтеров: %@", "Знайшла принтерів: %@"),
        "stSeen":       ("Looking for a printer… (%@ devices)", "Ищу принтер… (%@ устройств)", "Шукаю принтер… (%@ пристроїв)"),
        "stConnecting": ("Connecting to %@…", "Подключаюсь к %@…", "Підключаюсь до %@…"),
        "stFindingChan":("Connected, looking for the print channel…", "Подключено, ищу канал печати…", "Підключено, шукаю канал друку…"),
        "stReady":      ("Printer ready ✓", "Принтер готов ✓", "Принтер готовий ✓"),
        "stDone":       ("Done ✓", "Готово ✓", "Готово ✓"),
        "stFailed":     ("Could not connect. Try again.", "Не подключилось. Попробуй ещё раз.", "Не підключилось. Спробуй ще раз."),
        "stLost":       ("Printer disconnected", "Принтер отключился", "Принтер відключився"),
        "stBtOff":      ("Bluetooth is off", "Bluetooth выключен", "Bluetooth вимкнено"),
        "stBtDenied":   ("Allow Bluetooth: System Settings → Privacy → Bluetooth",
                         "Разреши Bluetooth: Настройки → Конфиденциальность → Bluetooth",
                         "Дозволь Bluetooth: Налаштування → Конфіденційність → Bluetooth"),
        "stBtNo":       ("Bluetooth unavailable", "Bluetooth недоступен", "Bluetooth недоступний"),
        "errNotConn":   ("Printer is not connected.", "Принтер не подключён.", "Принтер не підключено."),
        "errNoChannel": ("Connected, but the printer gave no channel to print through.",
                         "Принтер подключился, но не дал канал для печати.",
                         "Принтер підключився, але не дав канал для друку."),
]

