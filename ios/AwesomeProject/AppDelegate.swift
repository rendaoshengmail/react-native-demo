import UIKit
import React // 解决编译错误的关键
import React_RCTAppDelegate
import ReactAppDependencyProvider

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    
    // 保留新模板的属性
    var reactNativeDelegate: ReactNativeDelegate?
    var reactNativeFactory: RCTReactNativeFactory?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        
        self.window = UIWindow(frame: UIScreen.main.bounds)
        
        // 1. 启动时，首先展示“检查更新”的加载界面
        let updateVC = UpdateViewController()
        self.window?.rootViewController = updateVC
        self.window?.makeKeyAndVisible()

        // 2. 开始执行热更新检查流程
        RNHotUpdateManager.shared.checkAndUpdate { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                print("热更新流程出现错误（已处理）: \(error.localizedDescription)")
            }
            
            // 3. 更新流程结束，在主线程初始化并加载 React Native 主界面
            DispatchQueue.main.async {
                self.setupAndStartReactNative(launchOptions: launchOptions)
            }
        }
        
        return true
    }

    /// 初始化并使用新模板的工厂模式启动 React Native 应用
    func setupAndStartReactNative(launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) {
        // 使用我们自定义的代理，它将负责提供 JSBundle 的 URL
        let delegate = ReactNativeDelegate()
        let factory = RCTReactNativeFactory(delegate: delegate)
        delegate.dependencyProvider = RCTAppDependencyProvider()

        self.reactNativeDelegate = delegate
        self.reactNativeFactory = factory
        
        // 工厂方法会使用 delegate 中我们重写过的 sourceURL 方法
        factory.startReactNative(
          withModuleName: "AwesomeProject",
          in: self.window, // 在现有的 window 中启动
          launchOptions: launchOptions
        )
    }
}


// MARK: - ReactNativeDelegate

/// 这是适配新版 RN 项目模板的关键。
/// 我们通过自定义 Delegate，来告诉 React Native 工厂(factory)应该从哪里加载 JSBundle。
class ReactNativeDelegate: RCTDefaultReactNativeFactoryDelegate {

    /// 重写此方法，将 JSBundle 的来源指向我们的热更新管理器
    override func sourceURL(for bridge: RCTBridge) -> URL? {
        // 1. 优先使用热更新管理器提供的 URL
        if let url = RNHotUpdateManager.shared.jsBundleURL {
            print("ReactNativeDelegate: 加载 JSBundle from RNHotUpdateManager -> \(url.absoluteString)")
            return url
        }
        
        // 2. 如果热更新 URL 不存在，则使用备选方案
        #if DEBUG
            print("ReactNativeDelegate: fallback to Metro bundler.")
            return URL(string: "http://127.0.0.1:8081/index.bundle?platform=ios&dev=true&minify=false")
        #else
            print("ReactNativeDelegate: fallback to main bundle.")
            return Bundle.main.url(forResource: "main", withExtension: "jsbundle")
        #endif
    }
  
    // **新增此方法来解决崩溃问题**
    // 兼容新版 RCTAppDelegate/Factory 期望调用的方法
    override func bundleURL() -> URL? {
        // 直接调用或复用 sourceURL 的逻辑
        // 因为 RCTBridge 此时可能不可用，直接返回 RNHotUpdateManager.shared.jsBundleURL
        if let url = RNHotUpdateManager.shared.jsBundleURL {
             print("ReactNativeDelegate: 加载 JSBundle from RNHotUpdateManager (via bundleURL) -> \(url.absoluteString)")
             return url
        }
        
        #if DEBUG
            return URL(string: "http://127.0.0.1:8081/index.bundle?platform=ios&dev=true&minify=false")
        #else
            return Bundle.main.url(forResource: "main", withExtension: "jsbundle")
        #endif
    }
  
}

