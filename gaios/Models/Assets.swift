import Foundation
import UIKit
import PromiseKit

struct AssentEntity: Codable {
    let domain: String
}

struct AssetInfo: Codable {

    enum CodingKeys: String, CodingKey {
        case assetId = "asset_id"
        case name
        case precision
        case ticker
        case entity
    }

    var assetId: String
    var name: String
    var precision: UInt8?
    var ticker: String?
    var entity: AssentEntity?

    init(assetId: String, name: String, precision: UInt8, ticker: String) {
        self.assetId = assetId
        self.name = name
        self.precision = precision
        self.ticker = ticker
    }

    func encode() -> [String: Any]? {
        return try? JSONSerialization.jsonObject(with: JSONEncoder().encode(self), options: .allowFragments) as? [String: Any]
    }
}

class Assets {
    public static let shared = Assets()
    var info = [String: AssetInfo]()
    var icons = [String: String]()

    func image(for key: String?) -> UIImage? {
        let id = "btc" == key ? getGdkNetwork(getNetwork()).policyAsset! : key
        let icon = icons.filter { $0.key == id }.first
        if icon != nil {
            return UIImage(base64: icon!.value)
        }
        return UIImage(named: "default_asset_icon")
    }

    func refresh() -> Promise<([String: AssetInfo], [String: String])> {
        let bgq = DispatchQueue.global(qos: .background)
        return Promise().compactMap(on: bgq) { _ in
            try getSession().refreshAssets(params: ["icons": true, "assets": true])
        }.compactMap(on: bgq) { data in
            guard var assetsData = data["assets"] as? [String: Any] else { return nil }
            if let modIndex = assetsData.keys.firstIndex(of: "last_modified") {
                assetsData.remove(at: modIndex)
            }
            guard var iconsData = data["icons"] as? [String: String] else { return nil }
            if let modIndex = iconsData.keys.firstIndex(of: "last_modified") {
                iconsData.remove(at: modIndex)
            }
            let jsonAssets = try JSONSerialization.data(withJSONObject: assetsData)
            let jsonIcons = try JSONSerialization.data(withJSONObject: iconsData)
            self.info = try! JSONDecoder().decode([String: AssetInfo].self, from: jsonAssets)
            self.icons = try! JSONDecoder().decode([String: String].self, from: jsonIcons)
            return (self.info, self.icons)
        }
    }
}
