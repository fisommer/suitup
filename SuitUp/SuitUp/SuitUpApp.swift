import SwiftUI
 import SwiftData

 @main
 struct SuitUpApp: App {
     var sharedModelContainer: ModelContainer = {
         let schema = Schema([
             Item.self,
             Outfit.self,
             ReferenceLook.self,
             RecreateAttempt.self,
             WantedPiece.self,
             WearEvent.self,
             StylingRequest.self,
         ])
         let config = ModelConfiguration(schema: schema,
 isStoredInMemoryOnly: false)
         do {
             return try ModelContainer(for: schema, configurations:
 [config])
         } catch {
             fatalError("Could not create ModelContainer: \(error)")
         }
     }()

     var body: some Scene {
         WindowGroup {
             RootTabView()
         }
         .modelContainer(sharedModelContainer)
     }
 }
