import Foundation
import UIKit
import CryptoKit // 用于 MD5 校验
import SSZipArchive // <-- 确保已通过 Swift Package Manager 添加

// 定义版本信息的结构体，与服务器接口对应
struct RNVersionInfo: Codable {
    let rn_version: String
    let rn_zip_url: String
    let checksum: String
}

// 定义热更新过程中的错误类型
enum RNHotUpdateError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case serverError(statusCode: Int)
    case noData
    case jsonDecodingError(Error)
    case checksumMismatch
    case fileOperationError(String)
    case unzipFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的服务器地址。"
        case .networkError(let error): return "网络请求失败: \(error.localizedDescription)"
        case .serverError(let statusCode): return "服务器错误，状态码: \(statusCode)。"
        case .noData: return "服务器未返回有效数据。"
        case .jsonDecodingError: return "版本信息解析失败。"
        case .checksumMismatch: return "下载文件校验失败，文件可能已损坏。"
        case .fileOperationError(let msg): return "文件操作失败: \(msg)"
        case .unzipFailed: return "解压更新包失败。"
        }
    }
}


/// RNHotUpdateManager 是一个单例类，负责处理所有 React Native 热更新的逻辑。
/// 包括：版本检查、资源下载、文件校验、解压和应用。
final class RNHotUpdateManager {
    
    static let shared = RNHotUpdateManager()
    
    // MARK: - 配置项
    
    // TODO: 请将此 URL 替换为您自己的热更新版本检查接口
    private let updateCheckURL = URL(string: "http://127.0.0.1:3000/api/hotupdate")!
    
    // 当处于 DEBUG 模式时，设置此项为 true 来模拟和调试热更新流程
    // 生产环境 (Release build) 会忽略此开关，强制执行热更新流程
    private let debugHotUpdateFlow = true
    
    // MARK: - 公共属性
    
    // 最终提供给 RN 加载的 JSBundle 的 URL
    private(set) var jsBundleURL: URL?

    // MARK: - 私有属性
    
    private let fileManager = FileManager.default
    private lazy var rnBundlesDirectory: URL = {
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundlesDir = appSupportDir.appendingPathComponent("RN_Bundles")
        if !fileManager.fileExists(atPath: bundlesDir.path) {
            try? fileManager.createDirectory(at: bundlesDir, withIntermediateDirectories: true, attributes: nil)
        }
        return bundlesDir
    }()
    
    private lazy var versionInfoFile: URL = {
        return self.rnBundlesDirectory.appendingPathComponent("rn-version.json")
    }()
    
    // 从 Info.plist 读取的原生版本号
    private lazy var nativeAppVersion: String = {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }()

    // 从 Info.plist 读取的默认（初始）RN 版本号
    private lazy var defaultRNVersion: String = {
        return Bundle.main.object(forInfoDictionaryKey: "DefaultRNVersion") as? String ?? "1.0.0"
    }()

    private init() {
        // 私有化初始化方法，确保单例
        // 在初始化时，确定要使用的 jsBundleURL
        self.jsBundleURL = determineInitialJSBundleURL()
    }

    /// 决定 App 启动时应加载哪个 JSBundle
    private func determineInitialJSBundleURL() -> URL {
        // 1. 清理上次更新可能留下的临时文件
        cleanupTemporaryFiles()

        // 2. 读取本地记录的 RN 版本信息
        let localVersion = getLocalRNVersion()

        // 3. 检查该版本的 RN 包是否存在且有效
        let bundlePath = rnBundlesDirectory.appendingPathComponent(localVersion).appendingPathComponent("main.jsbundle")
        
        if fileManager.fileExists(atPath: bundlePath.path) {
            print("HotUpdate: 找到本地已解压的 RN 包，版本: \(localVersion)")
            return bundlePath
        }
        
        // 4. 如果本地没有有效的 RN 包（可能是首次启动或数据损坏）
        print("HotUpdate: 未找到本地有效的 RN 包。")
        
        // 尝试使用 App 内置的 main.jsbundle
        if let bundledURL = Bundle.main.url(forResource: "main", withExtension: "jsbundle") {
             print("HotUpdate: 使用 App 内置的 JSBundle。")
            return bundledURL
        }
        
        // 5. 如果 App 内也没有（调试模式下常见），则返回 Metro 的 URL
        #if DEBUG
            print("HotUpdate: 使用 Metro 服务器的 JSBundle。")
            // 更新：适配新版 RN，直接使用标准的 Metro URL
            guard let metroURL = URL(string: "http://127.0.0.1:8081/index.bundle?platform=ios&dev=true&minify=false") else {
                fatalError("无法创建 Metro Server 的 URL。")
            }
            return metroURL
        #else
            // 生产环境下，如果内置包也没有，这是严重错误。
            // 这里我们创建一个空的 URL，App 应该无法启动 RN，防止展示错误内容。
             print("HotUpdate FATAL: 生产环境下既无本地包也无内置包！")
            return URL(string: "file:///dev/null")!
        #endif
    }
    
    /// App 启动时的主入口函数，负责整个更新流程的调度
    func checkAndUpdate(completion: @escaping (Error?) -> Void) {
        // 在普通调试模式下，直接从 Metro 加载，跳过更新检查
        #if DEBUG
        if !debugHotUpdateFlow {
            print("HotUpdate: 普通调试模式，跳过更新检查。")
            guard let metroURL = URL(string: "http://127.0.0.1:8081/index.bundle?platform=ios&dev=true&minify=false") else {
                fatalError("无法创建 Metro Server 的 URL。")
            }
            self.jsBundleURL = metroURL
            completion(nil)
            return
        }
        #endif
        
        print("HotUpdate: 开始执行更新检查流程...")
        // 1. 从服务器获取最新版本信息
        fetchLatestVersionInfo { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .failure(let error):
                print("HotUpdate: 获取版本信息失败 - \(error.localizedDescription)。将继续使用本地版本。")
                completion(nil) // 获取版本失败，不阻塞启动，使用已有包
                
            case .success(let latestVersionInfo):
                let localVersion = self.getLocalRNVersion()
                let latestVersion = latestVersionInfo.rn_version
                print("HotUpdate: 本地版本: \(localVersion), 最新版本: \(latestVersion)")
                
                // 2. 比较版本，如果不需要更新，则直接完成
                if localVersion >= latestVersion {
                    print("HotUpdate: 本地已是最新版本。")
                    completion(nil)
                    return
                }
                
                // 3. 需要更新，开始下载
                print("HotUpdate: 发现新版本，开始下载...")
                self.downloadUpdate(from: latestVersionInfo) { downloadResult in
                    switch downloadResult {
                    case .failure(let error):
                        print("HotUpdate: 下载或校验失败 - \(error.localizedDescription)。将继续使用本地版本。")
                        completion(nil) // 下载失败，不阻塞启动
                        
                    case .success(let tempZipPath):
                        // 4. 下载并校验成功，应用更新
                        print("HotUpdate: 下载校验成功，开始应用更新...")
                        self.applyUpdate(from: tempZipPath, newVersionInfo: latestVersionInfo) { applyError in
                            if let error = applyError {
                                print("HotUpdate: 应用更新失败 - \(error.localizedDescription)。")
                            } else {
                                print("HotUpdate: 更新成功！新的 JSBundle 已准备就绪。")
                                // 更新成功后，更新 jsBundleURL
                                let newBundlePath = self.rnBundlesDirectory.appendingPathComponent(latestVersionInfo.rn_version).appendingPathComponent("main.jsbundle")
                                self.jsBundleURL = newBundlePath
                            }
                            // 无论应用更新成功与否，都通知 App 刷新或继续
                            // 成功则加载新包，失败则加载旧包
                            completion(applyError)
                        }
                    }
                }
            }
        }
    } // <-- **修复：这里添加了之前缺失的右花括号**

    // MARK: - 私有辅助函数

    private func getLocalRNVersion() -> String {
        guard let data = try? Data(contentsOf: versionInfoFile),
              let info = try? JSONDecoder().decode(RNVersionInfo.self, from: data) else {
            // 如果本地没有版本记录文件，则返回随 App 打包的默认版本
            return defaultRNVersion
        }
        return info.rn_version
    }

    private func saveLocalVersionInfo(_ versionInfo: RNVersionInfo) throws {
        do {
            let data = try JSONEncoder().encode(versionInfo)
            try data.write(to: versionInfoFile)
        } catch {
            throw RNHotUpdateError.fileOperationError("无法写入版本信息文件: \(error.localizedDescription)")
        }
    }
    
    private func fetchLatestVersionInfo(completion: @escaping (Result<RNVersionInfo, RNHotUpdateError>) -> Void) {
        var request = URLRequest(url: updateCheckURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["platform": "ios", "native_version": nativeAppVersion]
        request.httpBody = try? JSONEncoder().encode(body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(.networkError(error)))
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    completion(.failure(.serverError(statusCode: statusCode)))
                    return
                }
                guard let data = data else {
                    completion(.failure(.noData))
                    return
                }
                do {
                    let versionInfo = try JSONDecoder().decode(RNVersionInfo.self, from: data)
                    completion(.success(versionInfo))
                } catch {
                    completion(.failure(.jsonDecodingError(error)))
                }
            }
        }.resume()
    }
    
    private func downloadUpdate(from versionInfo: RNVersionInfo, completion: @escaping (Result<URL, RNHotUpdateError>) -> Void) {
        guard let url = URL(string: versionInfo.rn_zip_url) else {
            completion(.failure(.invalidURL))
            return
        }
        
        let downloadTask = URLSession.shared.downloadTask(with: url) { tempLocalURL, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(.networkError(error)))
                    return
                }
                guard let tempLocalURL = tempLocalURL else {
                    completion(.failure(.noData))
                    return
                }
                
                // 校验 MD5
                print("HotUpdate: 下载完成，开始计算 MD5...")
                if let checksum = self.calculateMD5(for: tempLocalURL), checksum.lowercased() == versionInfo.checksum.lowercased() {
                    print("HotUpdate: MD5 校验成功。")
                    completion(.success(tempLocalURL))
                } else {
                    print("HotUpdate: MD5 校验失败！本地: \(self.calculateMD5(for: tempLocalURL) ?? "nil"), 服务器: \(versionInfo.checksum)")
                    completion(.failure(.checksumMismatch))
                }
            }
        }
        downloadTask.resume()
    }
    
    /// 核心容错逻辑：应用更新
    private func applyUpdate(from tempZipPath: URL, newVersionInfo: RNVersionInfo, completion: @escaping (Error?) -> Void) {
        let newVersion = newVersionInfo.rn_version
        let destinationDir = rnBundlesDirectory.appendingPathComponent(newVersion)
        let tempUnzipDir = rnBundlesDirectory.appendingPathComponent("\(newVersion)_tmp")
        
        // 清理可能存在的上一次失败的临时解压目录
        if fileManager.fileExists(atPath: tempUnzipDir.path) {
            try? fileManager.removeItem(at: tempUnzipDir)
        }

        // 1. 解压到临时目录
        print("HotUpdate: 解压到临时目录 \(tempUnzipDir.path)...")
        let unzipSuccess = SSZipArchive.unzipFile(atPath: tempZipPath.path, toDestination: tempUnzipDir.path)
        if !unzipSuccess {
            // 如果解压失败，清理临时文件并抛出自定义错误
            try? fileManager.removeItem(at: tempUnzipDir)
            completion(RNHotUpdateError.unzipFailed)
            return
        }
        do {
            // 验证解压后文件是否存在
            let unzippedBundlePath = tempUnzipDir.appendingPathComponent("main.jsbundle")
            guard fileManager.fileExists(atPath: unzippedBundlePath.path) else {
                throw RNHotUpdateError.unzipFailed
            }
            print("HotUpdate: 解压成功。")
        } catch {
            try? fileManager.removeItem(at: tempUnzipDir) // 解压失败，清理垃圾
            completion(error)
            return
        }

        // 2. 原子性地替换旧目录
        // 通过重命名来完成，这是一个原子操作，能最大程度避免被中断时出现问题
        do {
            // 如果目标目录已存在（虽然版本检查逻辑上不应该），先移除
            if fileManager.fileExists(atPath: destinationDir.path) {
                 try fileManager.removeItem(at: destinationDir)
            }
            try fileManager.moveItem(at: tempUnzipDir, to: destinationDir)
            print("HotUpdate: 临时目录已成功重命名为目标目录。")
        } catch {
            try? fileManager.removeItem(at: tempUnzipDir) // 移动失败，清理垃圾
            completion(RNHotUpdateError.fileOperationError("无法将临时目录替换为目标目录: \(error.localizedDescription)"))
            return
        }

        // 3. 更新本地版本记录文件（这是“提交”操作）
        do {
            try saveLocalVersionInfo(newVersionInfo)
            print("HotUpdate: 本地版本记录已更新为 \(newVersion)。")
            completion(nil) // **成功**
        } catch {
            completion(error)
        }
    }
    
    private func cleanupTemporaryFiles() {
        do {
            let items = try fileManager.contentsOfDirectory(at: rnBundlesDirectory, includingPropertiesForKeys: nil)
            for item in items {
                if item.lastPathComponent.hasSuffix("_tmp") || item.lastPathComponent.hasSuffix("_old") {
                    print("HotUpdate: 清理上次遗留的临时文件: \(item.lastPathComponent)")
                    try? fileManager.removeItem(at: item)
                }
            }
        } catch {
            print("HotUpdate: 清理临时文件时出错: \(error.localizedDescription)")
        }
    }
    
    private func calculateMD5(for url: URL) -> String? {
        do {
            let data = try Data(contentsOf: url)
            let digest = Insecure.MD5.hash(data: data)
            return digest.map { String(format: "%02hhx", $0) }.joined()
        } catch {
            print("HotUpdate: 无法读取文件以计算 MD5: \(error.localizedDescription)")
            return nil
        }
    }
}


