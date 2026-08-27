import Foundation
import CoreBluetooth

/// Протокол M110-совместимых принтеров: ESC/POS-подобный диалект.
/// Команды идут ОТДЕЛЬНЫМИ записями с паузами — слитым потоком принтер мигает и
/// выбрасывает задание.
enum Proto {
    static let service    = CBUUID(string: "FF00")
    static let writeChar  = CBUUID(string: "FF02")
    static let notifyChar = CBUUID(string: "FF03")
    /// Сервисы, по которым узнаём принтер, если имя ничего не говорит.
    static let known = [CBUUID(string: "FF00"), CBUUID(string: "FFE0"),
                        CBUUID(string: "AE30"), CBUUID(string: "FEE7"),
                        CBUUID(string: "49535343-FE7D-4AE5-8FA9-9FAFD205E455")]
    /// Куски имени: китайские принтеры зовут себя как угодно, включая «Label Printer».
    static let names = ["LABEL", "PRINTER", "PHOMEMO", "M110", "M120", "M220", "M200",
                        "D30", "D110", "P12", "P50", "Q19", "MARKLIFE", "NIIMBOT",
                        "JADENS", "MUNBYN", "PT-", "HPRT"]

    static let chunk = 128
    static let chunkDelay: UInt64 = 20_000_000       // 20 мс
    static let cmdDelay: UInt64 = 30_000_000         // 30 мс
    static let beforeFooter: UInt64 = 300_000_000
    static let afterFooter: UInt64 = 500_000_000

    static func speed(_ v: Int) -> Data { Data([0x1b, 0x4e, 0x0d, UInt8(clamping: v)]) }
    static func density(_ v: Int) -> Data { Data([0x1b, 0x4e, 0x04, UInt8(clamping: v)]) }
    /// 0x0a — этикетки с зазором (наш рулон), 0x0b — сплошная лента, 0x26 — с метками.
    static func media(_ v: UInt8 = 0x0a) -> Data { Data([0x1f, 0x11, v]) }
    static func rasterHeader(lines: Int, bytesPerLine: Int = 48) -> Data {
        Data([0x1d, 0x76, 0x30, 0x00,
              UInt8(bytesPerLine & 0xff), UInt8(bytesPerLine >> 8),
              UInt8(lines & 0xff), UInt8((lines >> 8) & 0xff)])
    }
    static let footer = Data([0x1f, 0xf0, 0x05, 0x00, 0x1f, 0xf0, 0x03, 0x00])
}

/// Пишет ход дела в ~/Library/Logs/Sticker.log — по нему видно, что происходит с Bluetooth.
func logLine(_ s: String) {
    let dir = NSString(string: "~/Library/Logs").expandingTildeInPath
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let path = dir + "/Sticker.log"
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
    let line = "[\(f.string(from: Date()))] \(s)\n"
    if let h = FileHandle(forWritingAtPath: path) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    } else {
        try? line.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

/// Устройство в эфире.
struct Found: Identifiable, Equatable {
    let id: UUID
    let name: String
    var rssi: Int
    let likely: Bool          // похоже на принтер
    let peripheral: CBPeripheral
    static func == (a: Found, b: Found) -> Bool { a.id == b.id && a.rssi == b.rssi }
}

@MainActor
final class Printer: NSObject, ObservableObject {
    @Published var status = L10n.shared.t("stStarting")
    @Published var connected = false
    @Published var busy = false
    @Published var progress: Double = 0
    @Published var devices: [Found] = []
    @Published var connectedName = ""

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var write: CBCharacteristic?
    private var manual = false          // пользователь выбрал устройство сам

    /// Закреплённый принтер и фильтр по имени — чтобы у каждого работал свой аппарат.
    private let kPinned = "pinnedPrinter", kFilter = "printerNameFilter"
    @Published var pinnedID: String? = UserDefaults.standard.string(forKey: "pinnedPrinter")
    @Published var nameFilter: String = UserDefaults.standard.string(forKey: "printerNameFilter") ?? ""

    func pinCurrent() {
        guard let p = peripheral else { return }
        pinnedID = p.identifier.uuidString
        UserDefaults.standard.set(pinnedID, forKey: kPinned)
        logLine("закреплён принтер \(p.name ?? "?") \(pinnedID!)")
    }

    func unpin() {
        pinnedID = nil
        UserDefaults.standard.removeObject(forKey: kPinned)
        logLine("закрепление снято")
    }

    func setFilter(_ v: String) {
        nameFilter = v
        UserDefaults.standard.set(v, forKey: kFilter)
        logLine("фильтр имени: '\(v)'")
    }

    enum Err: LocalizedError {
        case notConnected, noChannel
        var errorDescription: String? {
            switch self {
            case .notConnected: return L10n.tr("errNotConn")
            case .noChannel: return L10n.tr("errNoChannel")
            }
        }
    }

    override init() {
        super.init()
        logLine("=== запуск приложения ===")
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        guard central.state == .poweredOn else { return }
        devices.removeAll()
        status = L10n.shared.t("stSearching")
        logLine("сканирую эфир")
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    /// Ручное подключение к выбранной строке списка.
    func connect(to f: Found) {
        manual = true
        central.stopScan()
        peripheral = f.peripheral
        f.peripheral.delegate = self
        status = L10n.shared.t("stConnecting").replacingOccurrences(of: "%@", with: f.name)
        logLine("подключаюсь вручную: \(f.name)")
        central.connect(f.peripheral)
    }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
    }

    private func isLikely(_ name: String?, _ adv: [String: Any]) -> Bool {
        let f = nameFilter.trimmingCharacters(in: .whitespaces).uppercased()
        if !f.isEmpty { return (name?.uppercased().contains(f)) ?? false }
        if let n = name?.uppercased(), Proto.names.contains(where: n.contains) { return true }
        if let uuids = adv[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            return uuids.contains { Proto.known.contains($0) }
        }
        return false
    }

    /// Печатает N копий одного растра. Между копиями — пауза, принтер не любит спешку.
    func print(raster: Data, lines: Int, layout: Layout) async throws {
        guard let p = peripheral, p.state == .connected else { throw Err.notConnected }
        guard let ch = write else { throw Err.noChannel }
        busy = true
        defer { busy = false; progress = 0 }

        let mode: CBCharacteristicWriteType =
            ch.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        logLine("печать: строк \(lines), байт \(raster.count), канал \(ch.uuid.uuidString)")

        for copy in 1...max(1, layout.copies) {
            status = layout.copies > 1
                ? L10n.shared.t("printingN")
                    .replacingOccurrences(of: "%@", with: "\(copy)", options: [], range: nil)
                    .replacingOccurrences(of: "%@", with: "\(layout.copies)")
                : L10n.shared.t("printing")

            p.writeValue(Proto.speed(layout.speed), for: ch, type: mode)
            try await Task.sleep(nanoseconds: Proto.cmdDelay)
            p.writeValue(Proto.density(layout.density), for: ch, type: mode)
            try await Task.sleep(nanoseconds: Proto.cmdDelay)
            p.writeValue(Proto.media(), for: ch, type: mode)
            try await Task.sleep(nanoseconds: Proto.cmdDelay)
            p.writeValue(Proto.rasterHeader(lines: lines), for: ch, type: mode)

            var sent = 0
            while sent < raster.count {
                let end = min(sent + Proto.chunk, raster.count)
                p.writeValue(raster.subdata(in: sent..<end), for: ch, type: mode)
                sent = end
                progress = Double(sent) / Double(raster.count)
                try await Task.sleep(nanoseconds: Proto.chunkDelay)
            }

            try await Task.sleep(nanoseconds: Proto.beforeFooter)
            p.writeValue(Proto.footer, for: ch, type: mode)
            try await Task.sleep(nanoseconds: Proto.afterFooter)
            if copy < layout.copies { try await Task.sleep(nanoseconds: 600_000_000) }
        }
        status = L10n.shared.t("stDone")
        logLine("печать отправлена")
    }
}

extension Printer: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ c: CBCentralManager) {
        Task { @MainActor in
            switch c.state {
            case .poweredOn: logLine("Bluetooth разрешён и включён"); startScan()
            case .poweredOff: status = L10n.shared.t("stBtOff")
            case .unauthorized: status = L10n.shared.t("stBtDenied")
            case .unsupported: status = L10n.shared.t("stBtNo")
            default: status = L10n.shared.t("stBtNo")
            }
            logLine("состояние Bluetooth: \(c.state.rawValue)")
        }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                                    advertisementData adv: [String: Any], rssi: NSNumber) {
        let name = p.name ?? (adv[CBAdvertisementDataLocalNameKey] as? String)
        let uuids = (adv[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
            .map { $0.uuidString }.joined(separator: ",") ?? "—"
        Task { @MainActor in
            guard !connected else { return }
            let likely = isLikely(name, adv)
            let shown = name ?? "без имени"
            if let i = devices.firstIndex(where: { $0.id == p.identifier }) {
                devices[i].rssi = rssi.intValue
            } else {
                logLine("вижу: \(shown) rssi=\(rssi) сервисы=\(uuids) похоже_на_принтер=\(likely)")
                devices.append(Found(id: p.identifier, name: shown, rssi: rssi.intValue,
                                     likely: likely, peripheral: p))
                devices.sort { ($0.likely ? 0 : 1, -$0.rssi) < ($1.likely ? 0 : 1, -$1.rssi) }
                if let pin = pinnedID, pin == p.identifier.uuidString, peripheral == nil {
                    connect(to: devices.first(where: { $0.id == p.identifier })!)
                    manual = false
                    return
                }
                if likely, !manual, pinnedID == nil, peripheral == nil {
                    connect(to: devices.first(where: { $0.id == p.identifier })!)
                    manual = false
                }
            }
            if peripheral == nil {
                let n = devices.filter(\.likely).count
                status = n > 0
                    ? L10n.shared.t("stFound").replacingOccurrences(of: "%@", with: "\(n)")
                    : L10n.shared.t("stSeen").replacingOccurrences(of: "%@", with: "\(devices.count)")
            }
        }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        Task { @MainActor in
            logLine("подключено к \(p.name ?? "?"), ищу сервисы")
            status = L10n.shared.t("stFindingChan")
            p.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            logLine("не удалось подключиться: \(error?.localizedDescription ?? "?")")
            status = L10n.shared.t("stFailed")
            peripheral = nil; manual = false
            startScan()
        }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            logLine("принтер отключился: \(error?.localizedDescription ?? "штатно")")
            connected = false; write = nil; peripheral = nil; connectedName = ""
            status = L10n.shared.t("stLost")
            startScan()
        }
    }

    nonisolated func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            for s in p.services ?? [] {
                logLine("сервис \(s.uuid.uuidString)")
                p.discoverCharacteristics(nil, for: s)
            }
        }
    }

    nonisolated func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService,
                                error: Error?) {
        Task { @MainActor in
            for ch in s.characteristics ?? [] {
                let w = ch.properties.contains(.write)
                let wn = ch.properties.contains(.writeWithoutResponse)
                logLine("  канал \(ch.uuid.uuidString) write=\(w) writeNoResp=\(wn) notify=\(ch.properties.contains(.notify))")
                // канал FF02 — приоритет; иначе берём первый пишущий
                if ch.uuid == Proto.writeChar { write = ch }
                else if write == nil, wn || w { write = ch }
                if ch.properties.contains(.notify) { p.setNotifyValue(true, for: ch) }
            }
            if let ch = write, !connected {
                connected = true
                connectedName = p.name ?? "принтер"
                status = L10n.shared.t("stReady")
                logLine("готов к печати, канал \(ch.uuid.uuidString)")
                central.stopScan()
            }
        }
    }

    nonisolated func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic,
                                error: Error?) {
        let hex = ch.value?.map { String(format: "%02x", $0) }.joined(separator: " ") ?? ""
        Task { @MainActor in logLine("ответ принтера: \(hex)") }
    }
}
