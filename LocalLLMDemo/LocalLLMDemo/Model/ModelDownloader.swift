import Foundation

/// 断点续传下载器（实战（一）「断点续传必须有」的代码落地）。
/// - 基于 URLSessionDownloadTask：暂停 / 取消时保存 resumeData，恢复时接着下。
/// - 处理了 iOS 偶发的「resumeData 失效」坑：失效就从头下，不打崩。
final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = ModelDownloader()

    private var session: URLSession!
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var resumeData: [String: Data] = [:]
    private var items: [String: ModelItem] = [:]
    private var progressHandlers: [String: (Double, Int64, Int64) -> Void] = [:]
    private var completionHandlers: [String: (Result<URL, Error>) -> Void] = [:]
    private let lock = NSLock()

    private override init() {
        super.init()
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.httpMaximumConnectionsPerHost = 4
        // 想要「退到后台 / Wi-Fi 自动续下」，把上面换成：
        // let cfg = URLSessionConfiguration.background(withIdentifier: "com.demo.llm")
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: OperationQueue())
    }

    /// 开始或继续下载（内部自动判断是否有可用的 resumeData）
    func fetch(item: ModelItem,
               progress: @escaping (Double, Int64, Int64) -> Void,
               completion: @escaping (Result<URL, Error>) -> Void) {
        lock.lock(); defer { lock.unlock() }
        items[item.id] = item
        progressHandlers[item.id] = progress
        completionHandlers[item.id] = completion

        if let data = resumeData[item.id], let task = session.downloadTask(withResumeData: data) {
            resumeData[item.id] = nil
            task.taskDescription = item.id
            tasks[item.id] = task
            task.resume()
        } else {
            let task = session.downloadTask(with: item.downloadURL)
            task.taskDescription = item.id
            tasks[item.id] = task
            task.resume()
        }
    }

    /// 暂停：保存 resumeData，下次 fetch 会接着下
    func pause(_ id: String) {
        lock.lock(); let task = tasks[id]; lock.unlock()
        task?.cancel(byProducingResumeData: { [weak self] data in
            self?.lock.lock()
            self?.resumeData[id] = data
            self?.tasks[id] = nil
            self?.lock.unlock()
        })
    }

    /// 取消：丢弃已下部分与 resumeData
    func cancel(_ id: String) {
        lock.lock(); let task = tasks[id]; lock.unlock()
        task?.cancel()
        lock.lock()
        tasks[id] = nil; resumeData[id] = nil
        lock.unlock()
    }

    func hasResumeData(_ id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return resumeData[id] != nil
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData b: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite e: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        let frac = e > 0 ? Double(w) / Double(e) : 0
        let clamped = max(0, min(1, frac))
        DispatchQueue.main.async { [weak self] in
            self?.progressHandlers[id]?(clamped, w, e)
        }
    }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription, let item = items[id] else { return }
        let dest = ModelStore.shared.localURL(for: item)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
            DispatchQueue.main.async { [weak self] in
                self?.progressHandlers[id]?(1, item.sizeBytes, item.sizeBytes)
                self?.completionHandlers[id]?(.success(dest))
                self?.cleanup(id)
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.completionHandlers[id]?(.failure(error))
                self?.cleanup(id)
            }
        }
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription else { return }
        // 正常完成已在 didFinishDownloadingTo 处理；这里只处理真正的失败 / 取消
        if let error {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled {
                return  // 主动 pause / cancel，不当成失败
            }
            DispatchQueue.main.async { [weak self] in
                self?.completionHandlers[id]?(.failure(error))
                self?.cleanup(id)
            }
        }
    }

    private func cleanup(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        progressHandlers[id] = nil
        completionHandlers[id] = nil
        tasks[id] = nil
    }
}
