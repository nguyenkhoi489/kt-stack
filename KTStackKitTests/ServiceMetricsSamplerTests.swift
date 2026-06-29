import XCTest
@testable import KTStackKit

final class ServiceMetricsSamplerTests: XCTestCase {
    func testParseCPUTimeMinuteOnly() {
        XCTAssertEqual(ServiceMetricsSampler.parseCPUTime("0:03.04")!, 3.04, accuracy: 0.001)
        XCTAssertEqual(ServiceMetricsSampler.parseCPUTime("51:10.24")!, 3070.24, accuracy: 0.001)
    }

    func testParseCPUTimeHourAndDay() {
        XCTAssertEqual(ServiceMetricsSampler.parseCPUTime("1:02:03")!, 3723, accuracy: 0.001)
        XCTAssertEqual(ServiceMetricsSampler.parseCPUTime("2-01:00:00")!, 176_400, accuracy: 0.001)
    }

    func testParseCPUTimeRejectsGarbage() {
        XCTAssertNil(ServiceMetricsSampler.parseCPUTime("abc"))
        XCTAssertNil(ServiceMetricsSampler.parseCPUTime(""))
    }

    func testParseExtractsBasenameAndConvertsRSS() {
        let raw = """
          100 200000  0:10.00 /opt/mysql/bin/mysqld
          600  20000  0:00.20 /Applications/My App/bin/mailpit
        """
        let rows = ServiceMetricsSampler.parse(raw)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].basename, "mysqld")
        XCTAssertEqual(rows[0].rssBytes, 200_000 * 1024)
        XCTAssertEqual(rows[1].basename, "mailpit")
    }

    func testParseMatchesNginxAndPHPFPMProcessTitles() {
        let raw = """
          98551  10416   0:00.03 nginx: master process /Users/x/Library/Application Support/KTStack/bin/nginx -g daemon off;
          98556   2160   0:00.00 nginx: worker process
          97005  13728   0:00.14 php-fpm: master process (/Users/x/Library/Application Support/KTStack/config/php-fpm/8.1.conf)
          97012  42240   0:00.14 php-fpm: pool 8.1
          400    30000   0:09.00 redis-server *:6379
        """
        let rows = ServiceMetricsSampler.parse(raw)
        XCTAssertEqual(
            rows.map(\.basename),
            ["nginx", "nginx", "php-fpm", "php-fpm", "redis-server"]
        )
    }

    func testAggregateSumsMultiProcessAndComputesCPUDelta() {
        let now = Date()
        let earlier = now.addingTimeInterval(-1)
        let current = [
            ParsedServiceProcess(pid: 200, rssBytes: 100_000 * 1024, cpuSeconds: 5.0, basename: "postgres"),
            ParsedServiceProcess(pid: 201, rssBytes: 80000 * 1024, cpuSeconds: 2.0, basename: "postgres"),
            ParsedServiceProcess(pid: 500, rssBytes: 10000 * 1024, cpuSeconds: 1.0, basename: "cupsd"),
        ]
        let previous: [Int32: ProcessCPUSample] = [
            200: ProcessCPUSample(cpuSeconds: 4.0, sampledAt: earlier),
            201: ProcessCPUSample(cpuSeconds: 1.0, sampledAt: earlier),
        ]

        let outcome = ServiceMetricsSampler.aggregate(current: current, previous: previous, now: now)

        let postgres = outcome.metrics[.postgres]
        XCTAssertNotNil(postgres)
        XCTAssertEqual(postgres!.cpuPercent, 200, accuracy: 0.001)
        XCTAssertEqual(postgres!.memoryBytes, Int64(180_000) * 1024)
        XCTAssertNil(outcome.metrics[.mysql])
        XCTAssertEqual(outcome.nextPrevious[200]?.cpuSeconds, 5.0)
    }

    func testAggregateFirstSeenPidCountsMemoryNotCPU() {
        let now = Date()
        let current = [
            ParsedServiceProcess(pid: 400, rssBytes: 30000 * 1024, cpuSeconds: 9.0, basename: "redis-server"),
        ]
        let outcome = ServiceMetricsSampler.aggregate(current: current, previous: [:], now: now)

        let redis = outcome.metrics[.redis]
        XCTAssertNotNil(redis)
        XCTAssertEqual(redis!.cpuPercent, 0, accuracy: 0.001)
        XCTAssertEqual(redis!.memoryBytes, Int64(30000) * 1024)
    }
}
