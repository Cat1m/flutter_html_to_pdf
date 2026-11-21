import Flutter
import UIKit
import WebKit

public class SwiftFlutterHtmlToPdfPlugin: NSObject, FlutterPlugin{
    var wkWebView : WKWebView!
    var urlObservation: NSKeyValueObservation?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_html_to_pdf", binaryMessenger: registrar.messenger())
    let instance = SwiftFlutterHtmlToPdfPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

    /// UIScene-safe key window lookup. `UIApplication.shared.delegate.window` is nil
    /// under UISceneDelegate (mandatory when building with the iOS 27 SDK), so resolve
    /// the key window from the connected window scenes instead.
    private static func sceneKeyWindow() -> UIWindow? {
        if #available(iOS 13.0, *) {
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
            return windows.first(where: { $0.isKeyWindow }) ?? windows.first
        }
        // iOS < 13 has no UIScene; fall back to the app delegate's window.
        return UIApplication.shared.delegate?.window ?? nil
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "convertHtmlToPdf":
        let args = call.arguments as? [String: Any]
        let htmlFilePath = args!["htmlFilePath"] as? String
        
        // !!! this is workaround for issue with rendering PDF images on iOS !!!
        guard let viewControler = SwiftFlutterHtmlToPdfPlugin.sceneKeyWindow()?.rootViewController else {
            result(FlutterError(code: "NO_KEY_WINDOW", message: "No key window available to render HTML to PDF", details: nil))
            return
        }
        wkWebView = WKWebView.init(frame: viewControler.view.bounds)
        wkWebView.isHidden = true
        wkWebView.tag = 100
        viewControler.view.addSubview(wkWebView)
        
        let htmlFileContent = FileHelper.getContent(from: htmlFilePath!) // get html content from file
        wkWebView.loadHTMLString(htmlFileContent, baseURL: Bundle.main.bundleURL) // load html into hidden webview
        
        urlObservation = wkWebView.observe(\.isLoading, changeHandler: { (webView, change) in
            // this is workaround for issue with loading local images
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let convertedFileURL = PDFCreator.create(printFormatter: self.wkWebView.viewPrintFormatter())
                let convertedFilePath = convertedFileURL.absoluteString.replacingOccurrences(of: "file://", with: "") // return generated pdf path
                if let viewWithTag = viewControler.view.viewWithTag(100) {
                    viewWithTag.removeFromSuperview() // remove hidden webview when pdf is generated
                    
                    // clear WKWebView cache
                    if #available(iOS 9.0, *) {
                        WKWebsiteDataStore.default().fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
                            records.forEach { record in
                                WKWebsiteDataStore.default().removeData(ofTypes: record.dataTypes, for: [record], completionHandler: {})
                            }
                        }
                    }
                }
                
                // dispose WKWebView
                self.urlObservation = nil
                self.wkWebView = nil
                result(convertedFilePath)
            }
        })
    default:
        result(FlutterMethodNotImplemented)
    }
  }
}
