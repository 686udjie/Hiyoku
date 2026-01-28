//
//  PlayerEpisode+Conversion.swift
//  Hiyoku
//
//  Created by 686udjie on 01/27/26.
//

import Foundation
import AidokuRunner

extension PlayerEpisode {
    func toChapter() -> AidokuRunner.Chapter {
        AidokuRunner.Chapter(
            key: self.url,
            title: self.title,
            chapterNumber: Float(self.number),
            dateUploaded: self.dateUploaded,
            scanlators: self.scanlator.map { [$0] },
            url: URL(string: self.url),
            language: self.language,
            locked: false
        )
    }
}

extension AidokuRunner.Chapter {
    func toNewChapter() -> PlayerEpisode {
        self.toPlayerEpisode()
    }

    func toPlayerEpisode() -> PlayerEpisode {
        PlayerEpisode(
            id: UUID(),
            number: Int(self.chapterNumber ?? 0),
            title: self.title ?? "",
            url: self.id,
            dateUploaded: self.dateUploaded,
            scanlator: self.scanlators?.first,
            language: self.language ?? "",
            subtitleUrl: nil
        )
    }
}
