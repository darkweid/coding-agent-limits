import Foundation
import QuotaOrbitsCore

enum CodexAppServerClientTests {
    static let cases: [TestCase] = [
        TestCase(name: "CodexAppServerClientTests.testProcessTransportRetainsFinalLineAfterChildExit") {
            let expected = Data(#"{"id":1,"result":{}}"#.utf8)
            let transport = ProcessJSONLineTransport(
                executable: URL(fileURLWithPath: "/usr/bin/printf"),
                arguments: [String(decoding: expected, as: UTF8.self) + "\n"]
            )

            try await transport.start()
            try await Task.sleep(for: .milliseconds(100))
            let received = try await transport.nextLine()
            await transport.stop()

            try TestSupport.assertEqual(received, expected)
        },
        TestCase(name: "CodexAppServerClientTests.testInitializesOnceThenReadsRateLimitsRepeatedly") {
            let transport = ScriptedJSONLineTransport(responses: [
                rpcLine(id: 1, result: #"{"userAgent":"test"}"#),
                rpcLine(id: 2, result: #"{"rateLimits":{}}"#),
                rpcLine(id: 3, result: #"{"rateLimits":{}}"#)
            ])
            let client = CodexAppServerClient(transport: transport)

            _ = try await client.rateLimitsResponse()
            _ = try await client.rateLimitsResponse()

            let sent = await transport.sentObjects()
            try TestSupport.assertEqual(sent.count, 4)
            try TestSupport.assertEqual(sent[0]["method"] as? String, "initialize")
            try TestSupport.assertEqual(sent[0]["id"] as? Int, 1)
            let initializeParams = sent[0]["params"] as? [String: Any]
            let clientInfo = initializeParams?["clientInfo"] as? [String: Any]
            try TestSupport.assertEqual(clientInfo?["name"] as? String, "quota_orbits")
            try TestSupport.assertEqual(clientInfo?["title"] as? String, "Quota Orbits")
            try TestSupport.assertEqual(clientInfo?["version"] as? String, "0.1.0")
            try TestSupport.assertEqual(sent[1]["method"] as? String, "initialized")
            try TestSupport.assertEqual(sent[1]["id"] as? Int, nil)
            try TestSupport.assertEqual(sent[2]["method"] as? String, "account/rateLimits/read")
            try TestSupport.assertEqual(sent[2]["id"] as? Int, 2)
            try TestSupport.assertEqual(sent[3]["method"] as? String, "account/rateLimits/read")
            try TestSupport.assertEqual(sent[3]["id"] as? Int, 3)
            try TestSupport.assertEqual(await transport.startCount, 1)
        },
        TestCase(name: "CodexAppServerClientTests.testClosureIsSanitizedAndNextCallReconnects") {
            let transport = ScriptedJSONLineTransport(outcomes: [
                .line(rpcLine(id: 1, result: #"{"userAgent":"test"}"#)),
                .closed,
                .line(rpcLine(id: 3, result: #"{"userAgent":"test"}"#)),
                .line(rpcLine(id: 4, result: #"{"rateLimits":{}}"#))
            ])
            let client = CodexAppServerClient(transport: transport)

            try await TestSupport.assertThrowsErrorAsync(
                try await client.rateLimitsResponse()
            ) { error in
                try TestSupport.assertEqual(
                    error as? CodexAppServerError,
                    .transportClosed
                )
            }

            let response = try await client.rateLimitsResponse()
            let object = try JSONSerialization.jsonObject(with: response) as? [String: Any]
            try TestSupport.assertEqual(object?["id"] as? Int, 4)
            try TestSupport.assertEqual(await transport.startCount, 2)

            let methods = await transport.sentObjects().compactMap { $0["method"] as? String }
            try TestSupport.assertEqual(
                methods,
                [
                    "initialize", "initialized", "account/rateLimits/read",
                    "initialize", "initialized", "account/rateLimits/read"
                ]
            )
        }
    ]

    private static func rpcLine(id: Int, result: String) -> Data {
        Data(#"{"id":\#(id),"result":\#(result)}"#.utf8)
    }
}
