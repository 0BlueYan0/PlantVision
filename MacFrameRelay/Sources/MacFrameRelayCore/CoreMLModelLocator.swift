import CoreML
import Foundation

/// Core ML 模型查找與編譯的共用邏輯。植物分類器與枯萎分類器共用同一套查找順序
/// （`.mlmodelc → .mlpackage → .mlmodel`，從打包進來的 `Resources/` 取用），
/// 避免兩處各寫一份而日後走樣。各分類器再用自己的錯誤型別包裝「找不到」的情況。
enum CoreMLModelLocator {
    static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }

    static func findModelURL(named modelName: String, in bundle: Bundle = resourceBundle) -> URL? {
        for fileExtension in ["mlmodelc", "mlpackage", "mlmodel"] {
            if let url = bundle.url(forResource: modelName, withExtension: fileExtension) {
                return url
            }
        }
        return nil
    }

    static func compiledModelURL(from modelURL: URL) throws -> URL {
        if modelURL.pathExtension == "mlmodelc" {
            return modelURL
        }
        return try MLModel.compileModel(at: modelURL)
    }
}
