import Foundation
import GRDB

/// Schema de la base. Une migration par version du schema, jamais modifiee
/// une fois publiee : on en ajoute une nouvelle (`v2`, `v3`...).
public enum Migrations {
    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        #if DEBUG
        m.eraseDatabaseOnSchemaChange = true
        #endif

        m.registerMigration("v1") { db in
            try db.create(table: "meta") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
            try db.create(table: "draft") { t in
                t.primaryKey("id", .text)
                t.column("text", .text).notNull()
                t.column("title", .text).notNull().defaults(to: "")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }

        // 0.3.0 : champs chiffres (titre et texte ; `text` et `title` restent vides quand ils
        // sont remplis) et correspondance avec les notes importees de l'app Notes. Le chiffrement
        // lui-meme demande la cle : il a lieu a l'activation (DraftStore.enableProtection).
        m.registerMigration("v2") { db in
            try db.alter(table: "draft") { t in
                t.add(column: "titleSealed", .blob)
                t.add(column: "textSealed", .blob)
            }
            try db.create(table: "notesImport") { t in
                t.primaryKey("notesId", .text)
                t.column("draftId", .text).notNull().indexed()
                    .references("draft", onDelete: .cascade)
                t.column("notesModifiedAt", .datetime).notNull()
                t.column("draftUpdatedAt", .datetime).notNull()
                t.column("importedAt", .datetime).notNull()
            }
        }

        return m
    }

    /// Applique les migrations jusqu'a `upTo` (toutes si nil). Pour les tests de migration.
    public static func migrate(_ writer: any DatabaseWriter, upTo target: String? = nil) throws {
        if let target {
            try migrator.migrate(writer, upTo: target)
        } else {
            try migrator.migrate(writer)
        }
    }
}
