import Foundation
@main struct WidgetSnapshotTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 1000)
        var s = JourneyWidgetSnapshot()
        s.online = true; s.stateAt = now; s.obdAt = now; s.bodyAt = now; s.healthAt = now; s.gpsAt = now
        s.rpm = 0; s.speed = 0; s.coolant = 90; s.locked = true; s.doorKnownMask = 86; s.doorOpenMask = 2; s.espTemperature = 40; s.latitude = 30; s.longitude = 47
        s.fuel = 45
        assert(s.expired(at: now).rpm == 0, "A valid zero must remain a zero")
        assert(s.door(2) == true && s.door(4) == false && s.door(8) == nil, "Unknown doors must never appear closed")
        let staleBody = s.expired(at: now.addingTimeInterval(6))
        assert(staleBody.rpm == nil && staleBody.locked == nil && staleBody.door(2) == nil)
        assert(staleBody.online && staleBody.espTemperature == 40 && staleBody.latitude == 30, "Independent sources expire independently")
        s.obdAt = now.addingTimeInterval(6)
        assert(s.expired(at: now.addingTimeInterval(6)).rpm == 0)
        assert(s.expired(at: now.addingTimeInterval(6)).locked == nil, "Fresh engine packets cannot revive stale doors")
        let offline = s.expired(at: now.addingTimeInterval(13))
        assert(!offline.online && offline.rpm == nil && offline.espTemperature == nil && offline.latitude == nil)
        assert(offline.fuel == 45, "Last confirmed fuel survives engine/connection expiry")
        assert(s.expired(at: now.addingTimeInterval(3600)).fuel == 45)
        assert(!s.fresh(now.addingTimeInterval(1), at: now, seconds: 5), "Reject future timestamps")
        let restored = try! JSONDecoder().decode(JourneyWidgetSnapshot.self, from: JSONEncoder().encode(s))
        assert(restored == s)
        var demo = JourneyWidgetSnapshot()
        demo.demoMode = true
        demo.online = true
        demo.deviceID = "journey-demo"
        demo.name = "JOURNEY DEMO"
        demo.rpm = 850
        demo.doorKnownMask = 2 | 4 | 8 | 16 | 32 | 64
        demo.doorOpenMask = 2 | 64
        demo.leftTurn = true
        demo.locked = false
        let futureDemo = demo.expired(at: now.addingTimeInterval(3600))
        assert(futureDemo == demo, "Demo must not expire as real vehicle telemetry")
        assert(futureDemo.door(2) == true && futureDemo.door(4) == false)
        assert(try! JSONDecoder().decode(JourneyWidgetSnapshot.self, from: JSONEncoder().encode(demo)) == demo)
        var changed = demo
        changed.leftTurn = false
        assert(changed.importantKey != demo.importantKey, "Demo indicator updates must refresh widgets")
        print("Widget snapshot checks passed")
    }
}
