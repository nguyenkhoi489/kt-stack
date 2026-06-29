import XCTest
@testable import KTStackKit

final class RouteIntrospectorParsingTests: XCTestCase {
    private func data(_ string: String) -> Data {
        Data(string.utf8)
    }

    func testParsesReflectionPayloadWithFormRequestFields() throws {
        let json = """
        {"error":null,"routes":[
          {"method":"POST","uri":"api/users","name":"users.store","middleware":["api","auth"],
           "action":"App\\\\Http\\\\Controllers\\\\UserController@store",
           "fields":[{"name":"email","rules":["required","email"],"required":true},
                     {"name":"age","rules":["integer"],"required":false}],
           "rulesResolved":true}
        ]}
        """
        let payload = try RouteIntrospector.parseReflectionPayload(data(json))
        XCTAssertNil(payload.error)
        XCTAssertEqual(payload.routes.count, 1)
        let route = payload.routes[0]
        XCTAssertEqual(route.method, "POST")
        XCTAssertEqual(route.uri, "api/users")
        XCTAssertTrue(route.isApi)
        XCTAssertTrue(route.rulesResolved)
        XCTAssertEqual(route.fields.count, 2)
        XCTAssertEqual(route.fields.first?.name, "email")
        XCTAssertTrue(route.fields.first?.required ?? false)
    }

    func testParsesReflectionErrorPayload() throws {
        let json = #"{"error":"Database connection refused","routes":[]}"#
        let payload = try RouteIntrospector.parseReflectionPayload(data(json))
        XCTAssertEqual(payload.error, "Database connection refused")
        XCTAssertTrue(payload.routes.isEmpty)
    }

    func testRouteWithoutFormRequestHasNoFields() throws {
        let json = """
        {"error":null,"routes":[
          {"method":"GET","uri":"/","name":null,"middleware":["web"],
           "action":"Closure","fields":[],"rulesResolved":false}
        ]}
        """
        let payload = try RouteIntrospector.parseReflectionPayload(data(json))
        let route = payload.routes[0]
        XCTAssertNil(route.name)
        XCTAssertFalse(route.isApi)
        XCTAssertTrue(route.isClosure)
        XCTAssertTrue(route.fields.isEmpty)
    }

    func testParsesRouteListJsonAndDropsHead() throws {
        let json = """
        [
          {"domain":null,"method":"GET|HEAD","uri":"api/posts","name":"posts.index",
           "action":"App\\\\Http\\\\Controllers\\\\PostController@index","middleware":["api"]},
          {"domain":null,"method":"DELETE","uri":"api/posts/{post}","name":null,
           "action":"Closure","middleware":"api\\nauth"}
        ]
        """
        let routes = try RouteIntrospector.parseRouteList(data(json))
        XCTAssertEqual(routes.count, 2)
        XCTAssertEqual(routes.first?.method, "GET")
        XCTAssertFalse(routes.contains { $0.method == "HEAD" })
        let deleteRoute = routes.first { $0.method == "DELETE" }
        XCTAssertEqual(deleteRoute?.uri, "api/posts/{post}")
        XCTAssertEqual(deleteRoute?.middleware, ["api", "auth"])
        XCTAssertTrue(routes.allSatisfy { !$0.rulesResolved })
    }

    func testJsonSliceTrimsSurroundingNoise() throws {
        let noisy = "PHP Warning: something\n{\"error\":null,\"routes\":[]}\n"
        let sliced = try XCTUnwrap(RouteIntrospector.jsonSlice(from: noisy))
        let payload = try RouteIntrospector.parseReflectionPayload(sliced)
        XCTAssertNil(payload.error)
        XCTAssertTrue(payload.routes.isEmpty)
    }

    func testJsonSliceExtractsBetweenMarkersDespiteBracketNoise() throws {
        let noisy = """
        Warning: Unable to load dynamic library (tried: [/opt/x.so] {bad})
        Deprecated: something {nested} here
        __KTSTACK_ROUTES_BEGIN__{"error":null,"routes":[{"method":"GET","uri":"a","name":null,"middleware":[],"action":"Closure","fields":[],"rulesResolved":false}]}__KTSTACK_ROUTES_END__
        trailing junk } ]
        """
        let sliced = try XCTUnwrap(RouteIntrospector.jsonSlice(from: noisy))
        let payload = try RouteIntrospector.parseReflectionPayload(sliced)
        XCTAssertNil(payload.error)
        XCTAssertEqual(payload.routes.count, 1)
        XCTAssertEqual(payload.routes.first?.uri, "a")
    }

    func testSortedOrdersByUriThenMethod() {
        let routes = [
            APIRoute(method: "POST", uri: "api/a", name: nil, middleware: [], action: "x", fields: [], rulesResolved: false),
            APIRoute(method: "GET", uri: "api/a", name: nil, middleware: [], action: "x", fields: [], rulesResolved: false),
            APIRoute(method: "GET", uri: "api/b", name: nil, middleware: [], action: "x", fields: [], rulesResolved: false),
        ]
        let sorted = RouteIntrospector.sorted(routes)
        XCTAssertEqual(sorted.map(\.id), ["GET api/a", "POST api/a", "GET api/b"])
    }
}
