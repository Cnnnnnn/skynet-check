import Foundation

// A global npm binary's package sits in `<bin>/../lib/node_modules`; the
// owning package is the one whose `bin` manifest names this executable
// (skynet-mcp → @shopee/skynet-base, banking-fe-mcp → @shopee/skynet.bank-fe-flow).
public enum NodeModulesPackageReader {
    public struct Package: Equatable, Sendable {
        public let name: String
        public let version: String
    }

    public static func package(
        owningBinary binaryName: String,
        inBinaryDirectory binaryDirectory: String,
        fileManager: FileManager = .default
    ) -> Package? {
        let nodeModulesURL = URL(fileURLWithPath: binaryDirectory)
            .deletingLastPathComponent()
            .appendingPathComponent("lib/node_modules")
        guard let scopes = try? fileManager.contentsOfDirectory(
            atPath: nodeModulesURL.path
        ) else {
            return nil
        }

        var candidates: [URL] = []
        for scope in scopes where !scope.hasPrefix(".") {
            let scopeURL = nodeModulesURL.appendingPathComponent(scope)
            var isDirectory: ObjCBool = false
            guard scope.hasPrefix("@"),
                  fileManager.fileExists(atPath: scopeURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                candidates.append(scopeURL)
                continue
            }
            guard let packages = try? fileManager.contentsOfDirectory(
                atPath: scopeURL.path
            ) else {
                continue
            }
            candidates.append(
                contentsOf: packages.map { scopeURL.appendingPathComponent($0) }
            )
        }

        for candidate in candidates {
            let manifestURL = candidate.appendingPathComponent("package.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let package = parsePackage(from: data),
                  package.binaries.contains(binaryName)
            else {
                continue
            }
            return Package(name: package.name, version: package.version)
        }
        return nil
    }

    struct PackageManifestInfo {
        let name: String
        let version: String
        let binaries: Set<String>
    }

    private static func parsePackage(from data: Data) -> PackageManifestInfo? {
        struct Manifest: Decodable {
            let name: String?
            let version: String?
            let bin: Bin?

            enum Bin: Decodable {
                case single(String)
                case multiple([String: String])

                init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    if let value = try? container.decode(String.self) {
                        self = .single(value)
                        return
                    }
                    self = .multiple(try container.decode([String: String].self))
                }

                var names: Set<String> {
                    switch self {
                    case let .single(name):
                        [name]
                    case let .multiple(mapping):
                        Set(mapping.keys)
                    }
                }
            }
        }

        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              let name = manifest.name,
              let version = manifest.version
        else {
            return nil
        }
        return PackageManifestInfo(
            name: name,
            version: version,
            binaries: manifest.bin?.names ?? []
        )
    }
}
