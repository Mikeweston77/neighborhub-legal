
import CoreData
import Foundation

// Ensure Core Data model classes are available

struct PersistenceController {
    static let shared = PersistenceController()
    
    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        // Create sample data for previews
        let sampleUser = User(context: viewContext)
        sampleUser.id = UUID()
        sampleUser.name = "John Doe"
        sampleUser.email = "john@example.com"
        sampleUser.address = "123 Main St"
        sampleUser.isVerified = true
        sampleUser.reputationScore = 4.5
        sampleUser.joinedDate = Date()
        
        let samplePost = Post(context: viewContext)
        samplePost.id = UUID()
        samplePost.title = "Welcome to the neighborhood!"
        samplePost.content = "Just moved in and excited to meet everyone. Looking forward to being part of this community!"
        samplePost.author = sampleUser
        samplePost.createdDate = Date()
        samplePost.category = "General"
        samplePost.likes = 5
        
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()
    
    let container: NSPersistentContainer
    
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "NeighborHub")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}

extension PersistenceController {
    func save() {
        let context = container.viewContext
        
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}
