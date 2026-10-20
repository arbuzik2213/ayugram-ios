import Flutter
import TDLibFramework

/// Мост между Dart и TDLib (JSON-интерфейс td_json_client).
/// Dart шлёт запросы через MethodChannel "ayu/td",
/// а все ответы и обновления TDLib приходят через EventChannel "ayu/td/events".
public final class TdPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var receiveThread: Thread?
  private let lock = NSLock()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = TdPlugin()
    let methods = FlutterMethodChannel(name: "ayu/td", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methods)
    let events = FlutterEventChannel(name: "ayu/td/events", binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "create":
      result(Int(td_create_client_id()))
    case "send":
      guard let args = call.arguments as? [String: Any],
            let client = args["client"] as? Int,
            let json = args["json"] as? String else {
        result(FlutterError(code: "bad_args", message: nil, details: nil))
        return
      }
      td_send(Int32(client), json)
      result(nil)
    case "execute":
      guard let json = call.arguments as? String else {
        result(FlutterError(code: "bad_args", message: nil, details: nil))
        return
      }
      if let res = td_execute(json) {
        result(String(cString: res))
      } else {
        result(nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    lock.lock()
    eventSink = events
    lock.unlock()
    if receiveThread == nil {
      let thread = Thread { [weak self] in
        while true {
          guard let res = td_receive(1.0) else { continue }
          let str = String(cString: res)
          DispatchQueue.main.async {
            guard let self = self else { return }
            self.lock.lock()
            let sink = self.eventSink
            self.lock.unlock()
            sink?(str)
          }
        }
      }
      thread.name = "tdlib-receive"
      thread.qualityOfService = .userInitiated
      receiveThread = thread
      thread.start()
    }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    lock.lock()
    eventSink = nil
    lock.unlock()
    return nil
  }
}
