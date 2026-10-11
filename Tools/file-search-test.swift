import Foundation

@main
struct FileSearchTests {
    static func main() async {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        // MARK: - FileItemKind

        check("kind raw value mapping for file", FileItemKind(rawValue: "file") == .file)
        check("kind raw value mapping for dir", FileItemKind(rawValue: "dir") == .directory)
        check("kind raw value mapping for link", FileItemKind(rawValue: "link") == .link)
        check("kind raw value mapping fallback for other", FileItemKind(rawValue: "other") == .other)
        check("kind system image for dir is folder", FileItemKind.directory.systemImage == "folder.fill")

        // MARK: - FileSearchItem

        let home = NSHomeDirectory()
        let testItem = FileSearchItem(
            path: "\(home)/Developer/fsearch/main.rs",
            kind: .file,
            size: 1048576, // 1 MB
            mtime: Date(timeIntervalSince1970: 1700000000),
            score: 120
        )

        check("name is extracted properly", testItem.name == "main.rs")
        check("parent path is extracted properly", testItem.parentPath == "\(home)/Developer/fsearch")
        check("abbreviated parent path replaces home with tilde", testItem.abbreviatedParentPath == "~/Developer/fsearch")
        check("size is formatted", !testItem.formattedSize.isEmpty)
        check("is not directory", !testItem.isDirectory)

        let dirItem = FileSearchItem(
            path: "\(home)/Developer/fsearch",
            kind: .directory,
            size: 0,
            mtime: Date(),
            score: 80
        )
        check("directory formatted size is empty", dirItem.formattedSize == "")
        check("is directory", dirItem.isDirectory)

        // MARK: - JSON Decoding

        let validJson = """
        {
            "id": 42,
            "ok": true,
            "took_us": 135,
            "hits": [
                {
                    "kind": "file",
                    "mtime": 1725000000,
                    "path": "/Users/assimgenshi/main.rs",
                    "score": 95,
                    "size": 2048
                },
                {
                    "kind": "dir",
                    "mtime": 1725000000,
                    "path": "/Users/assimgenshi/src",
                    "score": 85,
                    "size": 0
                }
            ]
        }
        """.data(using: .utf8)!

        do {
            let resp = try JSONDecoder().decode(FSearchResponse.self, from: validJson)
            check("decoded valid hits response ok is true", resp.ok == true)
            check("decoded query id matches", resp.id == 42)
            check("decoded took_us matches", resp.took_us == 135)
            check("decoded hit count is 2", resp.hits?.count == 2)
            check("first hit path matches", resp.hits?.first?.path == "/Users/assimgenshi/main.rs")
            check("first hit score matches", resp.hits?.first?.score == 95)
        } catch {
            check("failed to decode valid hits response: \(error)", false)
        }

        let errorJson = """
        {
            "id": 99,
            "ok": false,
            "error": "indexing..."
        }
        """.data(using: .utf8)!

        do {
            let resp = try JSONDecoder().decode(FSearchResponse.self, from: errorJson)
            check("decoded error response ok is false", resp.ok == false)
            check("error message matches", resp.error == "indexing...")
            check("error id matches", resp.id == 99)
        } catch {
            check("failed to decode error response: \(error)", false)
        }

        let statusJson = """
        {
            "ok": true,
            "entries": 8345210,
            "dirs": 120500,
            "overlay": 0,
            "event_id": 998877,
            "index_bytes": 760000000,
            "full_disk_access": true,
            "owner": true
        }
        """.data(using: .utf8)!

        do {
            let status = try JSONDecoder().decode(FSearchStatus.self, from: statusJson)
            check("status ok is true", status.ok == true)
            check("status entries count matches", status.entries == 8345210)
            check("status full_disk_access is true", status.full_disk_access == true)
            check("status owner is true", status.owner == true)
        } catch {
            check("failed to decode status response: \(error)", false)
        }

        if failures > 0 {
            print("\n\(failures) check(s) failed")
            exit(1)
        } else {
            print("\nAll file search checks passed.")
        }
    }
}
