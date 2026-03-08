import XCTest
@testable import NeighborHub

final class OpenWeatherMapServiceTests: XCTestCase {
    func testDecodeSampleJSON() throws {
        let bundle = Bundle(for: OpenWeatherMapServiceTests.self)
        guard let url = bundle.url(forResource: "openweather_sample", withExtension: "json") else {
            XCTFail("Fixture not found")
            return
        }
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(OpenWeatherMapResponse.self, from: data)
        XCTAssertEqual(decoded.name, "Testville")
        XCTAssertEqual(decoded.weather?.first?.description, "clear sky")
        XCTAssertEqual(decoded.main?.temp, 21.5)
    }
}
