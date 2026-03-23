import CoreData
import Foundation
import OSLog

enum PersistenceModel {
    static let name = "Colonnade"
}

final class PersistenceController: @unchecked Sendable {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    private let logger = Logger(subsystem: "ai.opencode.app", category: "persistence")

    init(inMemory: Bool = false) {
        let model = Self.makeModel()
        container = NSPersistentContainer(name: PersistenceModel.name, managedObjectModel: model)

        let description = NSPersistentStoreDescription()
        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        } else {
            description.url = Self.storeURL()
        }

        description.shouldMigrateStoreAutomatically = false
        description.shouldInferMappingModelAutomatically = false
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { [logger] _, error in
            if let error {
                logger.fault("Persistent store load failed: \(error.localizedDescription, privacy: .public)")
                fatalError("Failed to load persistent store: \(error.localizedDescription)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        container.viewContext.undoManager = nil
        container.viewContext.shouldDeleteInaccessibleFaults = true
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        context.undoManager = nil
        context.shouldDeleteInaccessibleFaults = true
        return context
    }

    func saveViewContextIfNeeded() {
        let context = container.viewContext
        guard context.hasChanges else { return }

        do {
            try context.save()
        } catch {
            logger.error("View context save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func storeURL() -> URL {
        let fileManager = FileManager.default
        let supportDirectory: URL

        do {
            supportDirectory = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent(PersistenceModel.name, isDirectory: true)

            try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        } catch {
            fatalError("Failed to prepare Application Support directory: \(error.localizedDescription)")
        }

        return supportDirectory.appendingPathComponent("Colonnade.sqlite")
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let workspace = NSEntityDescription()
        workspace.name = "WorkspaceEntity"
        workspace.managedObjectClassName = NSStringFromClass(WorkspaceEntity.self)

        let session = NSEntityDescription()
        session.name = "SessionEntity"
        session.managedObjectClassName = NSStringFromClass(SessionEntity.self)

        let message = NSEntityDescription()
        message.name = "MessageEntity"
        message.managedObjectClassName = NSStringFromClass(MessageEntity.self)

        let messagePart = NSEntityDescription()
        messagePart.name = "MessagePartEntity"
        messagePart.managedObjectClassName = NSStringFromClass(MessagePartEntity.self)

        let permission = NSEntityDescription()
        permission.name = "PermissionEntity"
        permission.managedObjectClassName = NSStringFromClass(PermissionEntity.self)

        let question = NSEntityDescription()
        question.name = "QuestionEntity"
        question.managedObjectClassName = NSStringFromClass(QuestionEntity.self)

        let todo = NSEntityDescription()
        todo.name = "TodoEntity"
        todo.managedObjectClassName = NSStringFromClass(TodoEntity.self)

        let pane = NSEntityDescription()
        pane.name = "SessionPaneEntity"
        pane.managedObjectClassName = NSStringFromClass(SessionPaneEntity.self)

        workspace.properties = [
            attribute("id", .stringAttributeType, indexed: true),
            attribute("directory", .stringAttributeType, indexed: true),
            attribute("projectName", .stringAttributeType),
            attribute("isSelected", .booleanAttributeType),
            attribute("lastSyncedAt", .dateAttributeType)
        ]

        session.properties = [
            attribute("id", .stringAttributeType, indexed: true),
            attribute("workspaceID", .stringAttributeType, indexed: true),
            attribute("payloadJSON", .stringAttributeType),
            attribute("slug", .stringAttributeType),
            attribute("projectID", .stringAttributeType),
            attribute("workspaceRefID", .stringAttributeType),
            attribute("directory", .stringAttributeType),
            attribute("parentID", .stringAttributeType),
            attribute("title", .stringAttributeType),
            attribute("version", .stringAttributeType),
            attribute("createdAtMS", .doubleAttributeType),
            attribute("updatedAtMS", .doubleAttributeType),
            attribute("compactingAtMS", .doubleAttributeType),
            attribute("archivedAtMS", .doubleAttributeType),
            attribute("summaryAdditions", .integer64AttributeType),
            attribute("summaryDeletions", .integer64AttributeType),
            attribute("summaryFiles", .integer64AttributeType),
            attribute("statusType", .stringAttributeType),
            attribute("statusLabel", .stringAttributeType),
            attribute("statusAttempt", .integer64AttributeType),
            attribute("statusNextMS", .doubleAttributeType),
            attribute("hasPendingPermission", .booleanAttributeType),
            attribute("todoCompletedCount", .integer64AttributeType),
            attribute("todoTotalCount", .integer64AttributeType),
            attribute("todoActionableCount", .integer64AttributeType),
            attribute("lastContextUsagePercent", .integer64AttributeType),
            attribute("lastMessageCreatedAtMS", .doubleAttributeType),
            attribute("sortUpdatedAtMS", .doubleAttributeType),
            attribute("selectedModelProviderID", .stringAttributeType),
            attribute("selectedModelID", .stringAttributeType),
            attribute("selectedThinkingLevel", .stringAttributeType)
        ]

        message.properties = [
            attribute("id", .stringAttributeType, indexed: true),
            attribute("sessionID", .stringAttributeType, indexed: true),
            attribute("payloadJSON", .stringAttributeType),
            attribute("roleRaw", .stringAttributeType),
            attribute("createdAtMS", .doubleAttributeType),
            attribute("completedAtMS", .doubleAttributeType),
            attribute("parentID", .stringAttributeType),
            attribute("agent", .stringAttributeType),
            attribute("modelProviderID", .stringAttributeType),
            attribute("modelID", .stringAttributeType),
            attribute("mode", .stringAttributeType),
            attribute("pathCwd", .stringAttributeType),
            attribute("pathRoot", .stringAttributeType),
            attribute("cost", .doubleAttributeType),
            attribute("tokenTotal", .integer64AttributeType),
            attribute("tokenInput", .integer64AttributeType),
            attribute("tokenOutput", .integer64AttributeType),
            attribute("tokenReasoning", .integer64AttributeType),
            attribute("tokenCacheRead", .integer64AttributeType),
            attribute("tokenCacheWrite", .integer64AttributeType),
            attribute("finish", .stringAttributeType),
            attribute("summaryJSON", .stringAttributeType),
            attribute("errorJSON", .stringAttributeType)
        ]

        messagePart.properties = [
            attribute("id", .stringAttributeType, indexed: true),
            attribute("sessionID", .stringAttributeType, indexed: true),
            attribute("messageID", .stringAttributeType, indexed: true),
            attribute("payloadJSON", .stringAttributeType),
            attribute("typeRaw", .stringAttributeType),
            attribute("text", .stringAttributeType),
            attribute("synthetic", .booleanAttributeType),
            attribute("ignored", .booleanAttributeType),
            attribute("startAtMS", .doubleAttributeType),
            attribute("endAtMS", .doubleAttributeType),
            attribute("compactedAtMS", .doubleAttributeType),
            attribute("metadataJSON", .stringAttributeType),
            attribute("callID", .stringAttributeType),
            attribute("tool", .stringAttributeType),
            attribute("stateStatus", .stringAttributeType),
            attribute("stateInputJSON", .stringAttributeType),
            attribute("stateRaw", .stringAttributeType),
            attribute("stateOutput", .stringAttributeType),
            attribute("stateTitle", .stringAttributeType),
            attribute("stateMetadataJSON", .stringAttributeType),
            attribute("stateError", .stringAttributeType),
            attribute("stateAttachmentsJSON", .stringAttributeType),
            attribute("mime", .stringAttributeType),
            attribute("filename", .stringAttributeType),
            attribute("url", .stringAttributeType),
            attribute("reason", .stringAttributeType),
            attribute("cost", .doubleAttributeType),
            attribute("tokenTotal", .integer64AttributeType),
            attribute("tokenInput", .integer64AttributeType),
            attribute("tokenOutput", .integer64AttributeType),
            attribute("tokenReasoning", .integer64AttributeType),
            attribute("tokenCacheRead", .integer64AttributeType),
            attribute("tokenCacheWrite", .integer64AttributeType),
            attribute("prompt", .stringAttributeType),
            attribute("partDescription", .stringAttributeType),
            attribute("agent", .stringAttributeType),
            attribute("modelProviderID", .stringAttributeType),
            attribute("modelID", .stringAttributeType),
            attribute("command", .stringAttributeType),
            attribute("name", .stringAttributeType),
            attribute("sourceValue", .stringAttributeType),
            attribute("sourceStart", .integer64AttributeType),
            attribute("sourceEnd", .integer64AttributeType),
            attribute("hashString", .stringAttributeType),
            attribute("filesJSON", .stringAttributeType),
            attribute("snapshot", .stringAttributeType)
        ]

        permission.properties = [
            attribute("id", .stringAttributeType, indexed: true),
            attribute("sessionID", .stringAttributeType, indexed: true),
            attribute("payloadJSON", .stringAttributeType),
            attribute("permission", .stringAttributeType),
            attribute("patternsJSON", .stringAttributeType),
            attribute("metadataJSON", .stringAttributeType),
            attribute("alwaysJSON", .stringAttributeType),
            attribute("toolMessageID", .stringAttributeType),
            attribute("toolCallID", .stringAttributeType),
            attribute("workspaceID", .stringAttributeType, indexed: true)
        ]

        question.properties = [
            attribute("id", .stringAttributeType, indexed: true),
            attribute("sessionID", .stringAttributeType, indexed: true),
            attribute("payloadJSON", .stringAttributeType),
            attribute("questionsJSON", .stringAttributeType),
            attribute("workspaceID", .stringAttributeType, indexed: true)
        ]

        todo.properties = [
            attribute("id", .stringAttributeType, indexed: true),
            attribute("sessionID", .stringAttributeType, indexed: true),
            attribute("payloadJSON", .stringAttributeType),
            attribute("content", .stringAttributeType),
            attribute("statusRaw", .stringAttributeType),
            attribute("priorityRaw", .stringAttributeType)
        ]

        pane.properties = [
            attribute("id", .stringAttributeType, indexed: true),
            attribute("workspaceID", .stringAttributeType, indexed: true),
            attribute("sessionID", .stringAttributeType, indexed: true),
            attribute("position", .integer64AttributeType),
            attribute("width", .doubleAttributeType),
            attribute("isHidden", .booleanAttributeType)
        ]

        for entity in [workspace, session, message, messagePart, permission, question, todo, pane] {
            for case let attribute as NSAttributeDescription in entity.properties {
                attribute.isOptional = true
            }

            entity.indexes = fetchIndexes(for: entity)
        }

        workspace.uniquenessConstraints = [["id"], ["directory"]]
        session.uniquenessConstraints = [["id"]]
        message.uniquenessConstraints = [["id"]]
        messagePart.uniquenessConstraints = [["id"]]
        permission.uniquenessConstraints = [["id"]]
        question.uniquenessConstraints = [["id"]]
        todo.uniquenessConstraints = [["id"]]
        pane.uniquenessConstraints = [["id"]]

        model.entities = [workspace, session, message, messagePart, permission, question, todo, pane]
        return model
    }
}

private func attribute(_ name: String, _ type: NSAttributeType, indexed: Bool = false) -> NSAttributeDescription {
    let attribute = NSAttributeDescription()
    attribute.name = name
    attribute.attributeType = type
    if indexed {
        attribute.userInfo = ["indexed": true]
    }
    return attribute
}

private func fetchIndexes(for entity: NSEntityDescription) -> [NSFetchIndexDescription] {
    entity.properties.compactMap { property in
        guard
            let attribute = property as? NSAttributeDescription,
            let isIndexed = attribute.userInfo?["indexed"] as? Bool,
            isIndexed,
            let entityName = entity.name
        else {
            return nil
        }

        let element = NSFetchIndexElementDescription(property: attribute, collationType: .binary)
        return NSFetchIndexDescription(name: "\(entityName)_\(attribute.name)_index", elements: [element])
    }
}

@objc(WorkspaceEntity)
final class WorkspaceEntity: NSManagedObject {
    @NSManaged var id: String?
    @NSManaged var directory: String?
    @NSManaged var projectName: String?
    @NSManaged var isSelected: NSNumber?
    @NSManaged var lastSyncedAt: Date?
}

@objc(SessionEntity)
final class SessionEntity: NSManagedObject {
    @NSManaged var id: String?
    @NSManaged var workspaceID: String?
    @NSManaged var payloadJSON: String?
    @NSManaged var slug: String?
    @NSManaged var projectID: String?
    @NSManaged var workspaceRefID: String?
    @NSManaged var directory: String?
    @NSManaged var parentID: String?
    @NSManaged var title: String?
    @NSManaged var version: String?
    @NSManaged var createdAtMS: NSNumber?
    @NSManaged var updatedAtMS: NSNumber?
    @NSManaged var compactingAtMS: NSNumber?
    @NSManaged var archivedAtMS: NSNumber?
    @NSManaged var summaryAdditions: NSNumber?
    @NSManaged var summaryDeletions: NSNumber?
    @NSManaged var summaryFiles: NSNumber?
    @NSManaged var statusType: String?
    @NSManaged var statusLabel: String?
    @NSManaged var statusAttempt: NSNumber?
    @NSManaged var statusNextMS: NSNumber?
    @NSManaged var hasPendingPermission: NSNumber?
    @NSManaged var todoCompletedCount: NSNumber?
    @NSManaged var todoTotalCount: NSNumber?
    @NSManaged var todoActionableCount: NSNumber?
    @NSManaged var lastContextUsagePercent: NSNumber?
    @NSManaged var lastMessageCreatedAtMS: NSNumber?
    @NSManaged var sortUpdatedAtMS: NSNumber?
    @NSManaged var selectedModelProviderID: String?
    @NSManaged var selectedModelID: String?
    @NSManaged var selectedThinkingLevel: String?
}

@objc(MessageEntity)
final class MessageEntity: NSManagedObject {
    @NSManaged var id: String?
    @NSManaged var sessionID: String?
    @NSManaged var payloadJSON: String?
    @NSManaged var roleRaw: String?
    @NSManaged var createdAtMS: NSNumber?
    @NSManaged var completedAtMS: NSNumber?
    @NSManaged var parentID: String?
    @NSManaged var agent: String?
    @NSManaged var modelProviderID: String?
    @NSManaged var modelID: String?
    @NSManaged var mode: String?
    @NSManaged var pathCwd: String?
    @NSManaged var pathRoot: String?
    @NSManaged var cost: NSNumber?
    @NSManaged var tokenTotal: NSNumber?
    @NSManaged var tokenInput: NSNumber?
    @NSManaged var tokenOutput: NSNumber?
    @NSManaged var tokenReasoning: NSNumber?
    @NSManaged var tokenCacheRead: NSNumber?
    @NSManaged var tokenCacheWrite: NSNumber?
    @NSManaged var finish: String?
    @NSManaged var summaryJSON: String?
    @NSManaged var errorJSON: String?
}

@objc(MessagePartEntity)
final class MessagePartEntity: NSManagedObject {
    @NSManaged var id: String?
    @NSManaged var sessionID: String?
    @NSManaged var messageID: String?
    @NSManaged var payloadJSON: String?
    @NSManaged var typeRaw: String?
    @NSManaged var text: String?
    @NSManaged var synthetic: NSNumber?
    @NSManaged var ignored: NSNumber?
    @NSManaged var startAtMS: NSNumber?
    @NSManaged var endAtMS: NSNumber?
    @NSManaged var compactedAtMS: NSNumber?
    @NSManaged var metadataJSON: String?
    @NSManaged var callID: String?
    @NSManaged var tool: String?
    @NSManaged var stateStatus: String?
    @NSManaged var stateInputJSON: String?
    @NSManaged var stateRaw: String?
    @NSManaged var stateOutput: String?
    @NSManaged var stateTitle: String?
    @NSManaged var stateMetadataJSON: String?
    @NSManaged var stateError: String?
    @NSManaged var stateAttachmentsJSON: String?
    @NSManaged var mime: String?
    @NSManaged var filename: String?
    @NSManaged var url: String?
    @NSManaged var reason: String?
    @NSManaged var cost: NSNumber?
    @NSManaged var tokenTotal: NSNumber?
    @NSManaged var tokenInput: NSNumber?
    @NSManaged var tokenOutput: NSNumber?
    @NSManaged var tokenReasoning: NSNumber?
    @NSManaged var tokenCacheRead: NSNumber?
    @NSManaged var tokenCacheWrite: NSNumber?
    @NSManaged var prompt: String?
    @NSManaged var partDescription: String?
    @NSManaged var agent: String?
    @NSManaged var modelProviderID: String?
    @NSManaged var modelID: String?
    @NSManaged var command: String?
    @NSManaged var name: String?
    @NSManaged var sourceValue: String?
    @NSManaged var sourceStart: NSNumber?
    @NSManaged var sourceEnd: NSNumber?
    @NSManaged var hashString: String?
    @NSManaged var filesJSON: String?
    @NSManaged var snapshot: String?
}

@objc(PermissionEntity)
final class PermissionEntity: NSManagedObject {
    @NSManaged var id: String?
    @NSManaged var sessionID: String?
    @NSManaged var payloadJSON: String?
    @NSManaged var permission: String?
    @NSManaged var patternsJSON: String?
    @NSManaged var metadataJSON: String?
    @NSManaged var alwaysJSON: String?
    @NSManaged var toolMessageID: String?
    @NSManaged var toolCallID: String?
    @NSManaged var workspaceID: String?
}

@objc(QuestionEntity)
final class QuestionEntity: NSManagedObject {
    @NSManaged var id: String?
    @NSManaged var sessionID: String?
    @NSManaged var payloadJSON: String?
    @NSManaged var questionsJSON: String?
    @NSManaged var workspaceID: String?
}

@objc(TodoEntity)
final class TodoEntity: NSManagedObject {
    @NSManaged var id: String?
    @NSManaged var sessionID: String?
    @NSManaged var payloadJSON: String?
    @NSManaged var content: String?
    @NSManaged var statusRaw: String?
    @NSManaged var priorityRaw: String?
}

@objc(SessionPaneEntity)
final class SessionPaneEntity: NSManagedObject {
    @NSManaged var id: String?
    @NSManaged var workspaceID: String?
    @NSManaged var sessionID: String?
    @NSManaged var position: NSNumber?
    @NSManaged var width: NSNumber?
    @NSManaged var isHidden: NSNumber?
}
