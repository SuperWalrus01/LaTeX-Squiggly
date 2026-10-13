#if DEBUG
import QuartzCore
import UIKit

/// Times each touch from the moment the screen sensed it to the frame that
/// shows the result, for `-measureLatency` in debug builds. Each line of
/// `latency.txt` in the temporary folder is one touch:
///
///   kind  sensed→handler  handler  handler→commit  commit→frame  total  footprintMB
///
/// in milliseconds. `down` is the key's pop-up appearing, `up` the
/// character going in. The host app drawing the text is not included.
@MainActor
final class LatencyProbe: NSObject {
    static let shared: LatencyProbe? =
        ProcessInfo.processInfo.arguments.contains("-measureLatency") ? LatencyProbe() : nil

    private struct Sample {
        let kind: String
        let sensed: CFTimeInterval
        let start: CFTimeInterval
        let end: CFTimeInterval
        var commit: CFTimeInterval?
    }

    private var samples: [Sample] = []
    private var link: CADisplayLink?
    private let file = FileManager.default.temporaryDirectory.appendingPathComponent("latency.txt")

    private override init() {
        super.init()
        try? "".write(to: file, atomically: true, encoding: .utf8)
    }

    func record(_ kind: String, sensed: CFTimeInterval, start: CFTimeInterval) {
        let index = samples.count
        samples.append(Sample(kind: kind, sensed: sensed, start: start, end: CACurrentMediaTime()))
        // Runs once this pass of the run loop has done everything, Core
        // Animation's commit of SwiftUI's changes included.
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue,
                                                          false, CFIndex.max) { observer, _ in
            MainActor.assumeIsolated { self.samples[index].commit = CACurrentMediaTime() }
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        if link == nil {
            link = CADisplayLink(target: self, selector: #selector(frame(_:)))
            link?.add(to: .main, forMode: .common)
        }
    }

    /// The first frame after a commit is the one that shows it.
    @objc private func frame(_ link: CADisplayLink) {
        var lines = ""
        samples.removeAll { sample in
            guard let commit = sample.commit, commit <= link.timestamp else { return false }
            let ms = { (a: CFTimeInterval, b: CFTimeInterval) in String(format: "%.2f", (b - a) * 1000) }
            lines += [sample.kind, ms(sample.sensed, sample.start), ms(sample.start, sample.end),
                      ms(sample.end, commit), ms(commit, link.targetTimestamp),
                      ms(sample.sensed, link.targetTimestamp), String(format: "%.1f", Self.footprintMB)]
                .joined(separator: " ") + "\n"
            return true
        }
        if !lines.isEmpty, let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(lines.utf8))
            try? handle.close()
        }
    }

    /// What iOS counts against an extension's memory limit.
    private static var footprintMB: Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }
}
#endif
