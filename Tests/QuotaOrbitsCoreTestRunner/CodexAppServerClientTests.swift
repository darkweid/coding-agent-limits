import Foundation
@_spi(Testing) import QuotaOrbitsCore

enum CodexAppServerClientTests {
    static let cases: [TestCase] = [
        TestCase(name: "CodexAppServerClientTests.testOutputChunkStreamPreservesCallbackOrder") {
            let chunks = OrderedOutputChunks()
            let expected = [Data("first".utf8), Data("second".utf8), Data("third".utf8)]

            expected.forEach(chunks.yield)
            chunks.finish()

            var received: [Data] = []
            for await chunk in chunks.stream {
                received.append(chunk)
            }
            try TestSupport.assertEqual(received, expected)
        },
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

            let sent = await transport.sentMessages()
            try TestSupport.assertEqual(sent.count, 4)
            try TestSupport.assertEqual(sent[0].method, "initialize")
            try TestSupport.assertEqual(sent[0].id, 1)
            try TestSupport.assertEqual(sent[0].clientName, "quota_orbits")
            try TestSupport.assertEqual(sent[0].clientTitle, "Quota Orbits")
            try TestSupport.assertEqual(sent[0].clientVersion, "0.1.0")
            try TestSupport.assertEqual(sent[1].method, "initialized")
            try TestSupport.assertEqual(sent[1].id, nil)
            try TestSupport.assertEqual(sent[2].method, "account/rateLimits/read")
            try TestSupport.assertEqual(sent[2].id, 2)
            try TestSupport.assertEqual(sent[3].method, "account/rateLimits/read")
            try TestSupport.assertEqual(sent[3].id, 3)
            try TestSupport.assertEqual(await transport.startCount, 1)
        },
        TestCase(name: "CodexAppServerClientTests.testConcurrentRequestsAreWrittenInIDOrder") {
            let transport = DelayingJSONLineTransport(delayedRequestID: 3)
            let client = CodexAppServerClient(transport: transport)
            _ = try await client.rateLimitsResponse()

            async let first = client.rateLimitsResponse()
            async let second = client.rateLimitsResponse()
            _ = try await (first, second)

            try TestSupport.assertEqual(
                await transport.sentRequestIDs(),
                [1, 2, 3, 4]
            )
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

            let methods = await transport.sentMessages().compactMap(\.method)
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
