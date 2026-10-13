import Foundation
import GRDB

/// Schema de la base. Une migration par version du schema, jamais modifiee
/// une fois publiee : on en ajoute une nouvelle (`v2`, `v3`...).
enum Migrations {
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

        return m
    }
}
