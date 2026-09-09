import Testing
@testable import RuriCore

struct GameLogTests {
    @Test func decodesMojangEventsAndPreservesStackTraces() {
        var formatter = GameLogFormatter()
        #expect(formatter.consume("native stderr") == ["native stderr"])
        #expect(formatter.consume(#"<log4j:Event logger="test" timestamp="1" level="ERROR" thread="Render thread">"#).isEmpty)
        #expect(formatter.consume("<log4j:Message><![CDATA[Something failed]]></log4j:Message>").isEmpty)
        #expect(formatter.consume("<log4j:Throwable><![CDATA[java.lang.Exception\n\tat example.Main]]></log4j:Throwable>").isEmpty)
        #expect(formatter.consume("</log4j:Event>") == ["[Render thread/ERROR] Something failed", "java.lang.Exception", "\tat example.Main"])
        #expect(formatter.flush().isEmpty)
    }
    @Test func preservesIncompleteEventsAtExit() {
        var formatter = GameLogFormatter()
        let partial = #"<log4j:Event logger="test">"#
        #expect(formatter.consume(partial).isEmpty)
        #expect(formatter.flush() == [partial + "\n"])
    }
}
