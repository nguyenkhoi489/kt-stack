import XCTest
@testable import KTStackKit

final class GenericRouteDiscoveryParsingTests: XCTestCase {
    func testOpenAPIParsesMethodsAndNames() {
        let spec: [String: Any] = [
            "openapi": "3.0.3",
            "paths": [
                "/devices": [
                    "post": ["summary": "Register device"],
                    "get": ["operationId": "listDevices"],
                ],
                "/exams/{id}": [
                    "get": ["summary": "Show exam"],
                    "head": ["summary": "ignored"],
                ],
            ],
        ]
        let routes = OpenAPIRouteDiscovery.parse(spec)
        XCTAssertEqual(routes.count, 3)
        XCTAssertFalse(routes.contains { $0.method == "HEAD" })
        let post = routes.first { $0.uri == "devices" && $0.method == "POST" }
        XCTAssertEqual(post?.name, "Register device")
        let list = routes.first { $0.uri == "devices" && $0.method == "GET" }
        XCTAssertEqual(list?.name, "listDevices")
        XCTAssertTrue(routes.contains { $0.uri == "exams/{id}" && $0.method == "GET" })
    }

    func testOpenAPIAppliesServerBasePath() {
        let spec: [String: Any] = [
            "servers": [["url": "https://host.test/api/v1"]],
            "paths": ["/users": ["get": [:]]],
        ]
        let routes = OpenAPIRouteDiscovery.parse(spec)
        XCTAssertEqual(routes.first?.uri, "api/v1/users")
    }

    func testOpenAPIEmptyWhenNoPaths() {
        XCTAssertTrue(OpenAPIRouteDiscovery.parse(["openapi": "3.0.3"]).isEmpty)
    }

    func testPostmanCollectsNestedFoldersAndPathArray() {
        let items: [[String: Any]] = [
            ["name": "Folder", "item": [
                [
                    "name": "Register device",
                    "request": [
                        "method": "POST",
                        "url": ["raw": "{{base_url}}/devices", "host": ["{{base_url}}"], "path": ["devices"]],
                    ],
                ],
            ]],
            [
                "name": "Show exam",
                "request": [
                    "method": "GET",
                    "url": ["raw": "{{base_url}}/exams/:id", "path": ["exams", ":id"]],
                ],
            ],
        ]
        var routes: [APIRoute] = []
        PostmanCollectionDiscovery.collect(items: items, into: &routes)
        XCTAssertEqual(routes.count, 2)
        XCTAssertTrue(routes.contains { $0.method == "POST" && $0.uri == "devices" && $0.name == "Register device" })
        XCTAssertTrue(routes.contains { $0.method == "GET" && $0.uri == "exams/{id}" })
    }

    func testPostmanParsesRawURLWithQueryAndBaseURL() {
        XCTAssertEqual(PostmanCollectionDiscovery.path(from: "{{base_url}}/catalog/items?page=1"), "catalog/items")
        XCTAssertEqual(PostmanCollectionDiscovery.path(from: "https://api.test/v2/users/:uid"), "v2/users/{uid}")
    }

    func testPostmanKeepsMidPathVariableAsParam() {
        XCTAssertEqual(PostmanCollectionDiscovery.path(from: "{{base_url}}/users/{{userId}}/posts"), "users/{userId}/posts")
        let route = PostmanCollectionDiscovery.route(
            from: ["method": "GET", "url": ["path": ["users", "{{userId}}", "posts"]]], name: "Posts"
        )
        XCTAssertEqual(route?.uri, "users/{userId}/posts")
    }

    func testPostmanSkipsHeadAndNonRequestItems() {
        let items: [[String: Any]] = [
            ["name": "doc only"],
            ["name": "head probe", "request": ["method": "HEAD", "url": ["path": ["ping"]]]],
        ]
        var routes: [APIRoute] = []
        PostmanCollectionDiscovery.collect(items: items, into: &routes)
        XCTAssertTrue(routes.isEmpty)
    }
}
