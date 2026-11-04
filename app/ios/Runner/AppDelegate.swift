import Flutter
import UIKit
import WorkoutKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Geplante Läufe als Workouts in die Training-App der Apple Watch legen (WorkoutKit, ab iOS 17)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WorkoutKitBridge") {
      let channel = FlutterMethodChannel(name: "hyrox/workoutkit", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard #available(iOS 17.0, *) else {
          result(FlutterError(code: "unsupported", message: "Benötigt iOS 17 oder neuer.", details: nil))
          return
        }
        switch call.method {
        case "isSupported":
          result(WorkoutScheduler.isSupported)
        case "sync":
          let items = (call.arguments as? [[String: Any]]) ?? []
          Task {
            do {
              let count = try await WorkoutKitBridge.sync(items)
              result(count)
            } catch {
              result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
            }
          }
        case "clear":
          Task {
            await WorkoutKitBridge.clear()
            result(nil)
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}

/// Übersetzt die Läufe aus dem Plan (von Flutter als einfache Maps geliefert) in WorkoutKit-Workouts.
///
/// Format eines Eintrags:
///   date "yyyy-MM-dd", hour Int, name String,
///   warmup / cooldown: { distanceM?, durationSec? },
///   blocks: [ { iterations, work: { distanceM?, durationSec?, paceSecPerKm? }, recoverySec? } ]
@available(iOS 17.0, *)
enum WorkoutKitBridge {
  struct BridgeError: LocalizedError {
    let errorDescription: String?
  }

  static func clear() async {
    let scheduler = WorkoutScheduler.shared
    for workout in await scheduler.scheduledWorkouts {
      await scheduler.remove(workout.plan, at: workout.date)
    }
  }

  /// Ersetzt alle von dieser App geplanten Workouts durch die übergebenen. Gibt die Anzahl zurück.
  static func sync(_ items: [[String: Any]]) async throws -> Int {
    guard WorkoutScheduler.isSupported else {
      throw BridgeError(errorDescription: "Workouts planen wird auf diesem Gerät nicht unterstützt (keine Apple Watch gekoppelt?).")
    }
    let scheduler = WorkoutScheduler.shared
    var state = await scheduler.authorizationState
    if state != .authorized {
      state = await scheduler.requestAuthorization()
    }
    guard state == .authorized else {
      throw BridgeError(errorDescription: "Kein Zugriff auf die Workout-Planung erlaubt.")
    }

    await clear()

    var count = 0
    for item in items.prefix(WorkoutScheduler.maxAllowedScheduledWorkoutCount) {
      guard let date = item["date"] as? String, let name = item["name"] as? String else { continue }
      let parts = date.split(separator: "-").compactMap { Int($0) }
      guard parts.count == 3 else { continue }

      let blocks = ((item["blocks"] as? [[String: Any]]) ?? []).map(block)
      let workout = CustomWorkout(
        activity: .running,
        location: .outdoor,
        displayName: name,
        warmup: step(item["warmup"] as? [String: Any]),
        blocks: blocks,
        cooldown: step(item["cooldown"] as? [String: Any])
      )
      var when = DateComponents()
      when.year = parts[0]
      when.month = parts[1]
      when.day = parts[2]
      when.hour = (item["hour"] as? Int) ?? 7
      await scheduler.schedule(WorkoutPlan(.custom(workout)), at: when)
      count += 1
    }
    return count
  }

  private static func goal(_ m: [String: Any]) -> WorkoutGoal {
    if let meters = m["distanceM"] as? Double, meters > 0 { return .distance(meters, .meters) }
    if let meters = m["distanceM"] as? Int, meters > 0 { return .distance(Double(meters), .meters) }
    if let sec = m["durationSec"] as? Int, sec > 0 { return .time(Double(sec), .seconds) }
    return .open
  }

  private static func step(_ m: [String: Any]?) -> WorkoutStep? {
    guard let m else { return nil }
    return WorkoutStep(goal: goal(m))
  }

  /// Pace-Alarm: ±10 s/km um die Zielpace, als Geschwindigkeitsbereich in m/s.
  private static func paceAlert(_ paceSecPerKm: Int?) -> SpeedRangeAlert? {
    guard let pace = paceSecPerKm, pace > 120 else { return nil }
    let slow = Measurement(value: 1000.0 / Double(pace + 10), unit: UnitSpeed.metersPerSecond)
    let fast = Measurement(value: 1000.0 / Double(pace - 10), unit: UnitSpeed.metersPerSecond)
    return SpeedRangeAlert(target: slow...fast, metric: .current)
  }

  private static func block(_ m: [String: Any]) -> IntervalBlock {
    let work = (m["work"] as? [String: Any]) ?? [:]
    var steps = [IntervalStep(.work, goal: goal(work), alert: paceAlert(work["paceSecPerKm"] as? Int))]
    if let rest = m["recoverySec"] as? Int, rest > 0 {
      steps.append(IntervalStep(.recovery, goal: .time(Double(rest), .seconds)))
    }
    return IntervalBlock(steps: steps, iterations: max(1, (m["iterations"] as? Int) ?? 1))
  }
}
