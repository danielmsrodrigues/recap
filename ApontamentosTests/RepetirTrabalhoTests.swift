import Foundation
import Testing
@testable import Apontamentos

/// Repetir um trabalho que falhou depois dos slides: as capturas já foram apagadas e os slides não podem ir com elas.
struct RepetirTrabalhoTests {
    @Test func semAsCapturasDaJanelaNaoSeVoltaAExtrairSlides() throws {
        let frames = FileManager.default.temporaryDirectory.appending(path: "frames-\(UUID().uuidString)")
        #expect(PipelineRunner.capturasPorAnalisar(frames) == nil)
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: frames) }
        #expect(PipelineRunner.capturasPorAnalisar(frames) == frames)
        #expect(PipelineRunner.capturasPorAnalisar(nil) == nil)
    }
}
