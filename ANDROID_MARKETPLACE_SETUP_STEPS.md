# Android Marketplace - Step-by-Step Setup Guide
**After pasting the code into `/Users/mike/Desktop/Waterfall/NeighborHub_Android`**

---

## 📋 Step 1: Add Dependencies (5 min)

Open `app/build.gradle` and add:

```gradle
dependencies {
    // Firebase (if not already added)
    implementation platform('com.google.firebase:firebase-bom:32.7.0')
    implementation 'com.google.firebase:firebase-firestore-ktx'
    implementation 'com.google.firebase:firebase-storage-ktx'
    implementation 'com.google.firebase:firebase-auth-ktx'
    
    // Coroutines (if not already added)
    implementation 'org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3'
    implementation 'org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.7.3'
    
    // Room Database
    def room_version = "2.6.1"
    implementation "androidx.room:room-runtime:$room_version"
    implementation "androidx.room:room-ktx:$room_version"
    kapt "androidx.room:room-compiler:$room_version"
    
    // Image loading (choose one)
    implementation 'com.github.bumptech.glide:glide:4.16.0'
    kapt 'com.github.bumptech.glide:compiler:4.16.0'
    // OR
    implementation "io.coil-kt:coil:2.5.0"
    
    // Gson for JSON
    implementation 'com.google.code.gson:gson:2.10.1'
}

// Enable kapt at top of file
plugins {
    id 'kotlin-kapt'
}
```

**Then sync Gradle**

---

## 📁 Step 2: Create File Structure (10 min)

Create these folders and files in your Android project:

```
app/src/main/java/com/neighborhub/app/
├── models/
│   ├── MarketplaceItem.kt          ← Paste data model code
│   ├── ItemCondition.kt            ← Paste enum
│   └── PickupOption.kt             ← Paste enum
├── managers/
│   ├── MarketplaceManager.kt       ← Paste main manager code
│   └── ImageCacheManager.kt        ← Paste image cache code
├── database/
│   ├── AppDatabase.kt              ← Create database
│   ├── MarketplaceDao.kt           ← Paste DAO code
│   └── MarketplaceItemEntity.kt    ← Paste entity code
└── ui/marketplace/
    ├── MarketplaceFragment.kt      ← Your list view
    ├── AddListingDialog.kt         ← Create listing dialog
    └── MarketplaceAdapter.kt       ← RecyclerView adapter
```

---

## 🔧 Step 3: Create Database (15 min)

### 3.1 Create `AppDatabase.kt`

```kotlin
package com.neighborhub.app.database

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(
    entities = [MarketplaceItemEntity::class],
    version = 1,
    exportSchema = false
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun marketplaceDao(): MarketplaceDao
    
    companion object {
        @Volatile
        private var INSTANCE: AppDatabase? = null
        
        fun getDatabase(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "neighborhub_database"
                ).build()
                INSTANCE = instance
                instance
            }
        }
    }
}
```

### 3.2 Paste `MarketplaceDao.kt` and `MarketplaceItemEntity.kt` from the guide

---

## 🎨 Step 4: Create UI Components (30 min)

### 4.1 Create `MarketplaceFragment.kt`

```kotlin
package com.neighborhub.app.ui.marketplace

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.fragment.app.Fragment
import androidx.recyclerview.widget.LinearLayoutManager
import com.neighborhub.app.databinding.FragmentMarketplaceBinding
import com.neighborhub.app.managers.MarketplaceManager
import com.neighborhub.app.models.MarketplaceItem

class MarketplaceFragment : Fragment() {
    
    private var _binding: FragmentMarketplaceBinding? = null
    private val binding get() = _binding!!
    
    private lateinit var marketplaceManager: MarketplaceManager
    private lateinit var adapter: MarketplaceAdapter
    private val items = mutableListOf<MarketplaceItem>()
    
    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentMarketplaceBinding.inflate(inflater, container, false)
        return binding.root
    }
    
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        
        // Initialize manager
        marketplaceManager = MarketplaceManager(requireContext())
        
        // Setup RecyclerView
        adapter = MarketplaceAdapter(
            items = items,
            onItemClick = { item -> showItemDetails(item) },
            onDeleteClick = { item -> deleteItem(item) },
            onMarkSoldClick = { item -> toggleSold(item) }
        )
        
        binding.recyclerView.layoutManager = LinearLayoutManager(requireContext())
        binding.recyclerView.adapter = adapter
        
        // Add button
        binding.fabAdd.setOnClickListener {
            showAddListingDialog()
        }
        
        // Start watching for updates
        startWatching()
    }
    
    private fun startWatching() {
        marketplaceManager.watchMarketplace { updatedItems ->
            items.clear()
            items.addAll(updatedItems)
            adapter.notifyDataSetChanged()
            
            binding.emptyView.visibility = if (items.isEmpty()) View.VISIBLE else View.GONE
        }
    }
    
    private fun showAddListingDialog() {
        val dialog = AddListingDialog()
        dialog.setOnCreateListener { title, description, price, category, condition, 
                                     primaryImage, additionalImages, contact, location ->
            
            marketplaceManager.createMarketplaceListing(
                title = title,
                description = description,
                price = price,
                category = category,
                condition = condition,
                primaryImage = primaryImage,
                additionalImages = additionalImages,
                contact = contact,
                location = location,
                onProgress = { type, progress ->
                    // Update progress UI
                    dialog.updateProgress(type, progress)
                },
                onComplete = { result ->
                    result.onSuccess {
                        dialog.dismiss()
                        Toast.makeText(context, "Listing created!", Toast.LENGTH_SHORT).show()
                    }.onFailure { error ->
                        Toast.makeText(context, "Error: ${error.message}", Toast.LENGTH_LONG).show()
                    }
                }
            )
        }
        dialog.show(childFragmentManager, "AddListingDialog")
    }
    
    private fun deleteItem(item: MarketplaceItem) {
        // Show confirmation dialog
        androidx.appcompat.app.AlertDialog.Builder(requireContext())
            .setTitle("Delete Listing")
            .setMessage("Are you sure you want to delete \"${item.title}\"?")
            .setPositiveButton("Delete") { _, _ ->
                marketplaceManager.deleteMarketplaceListing(item.id) { result ->
                    result.onSuccess {
                        Toast.makeText(context, "Item deleted", Toast.LENGTH_SHORT).show()
                    }.onFailure { error ->
                        Toast.makeText(context, "Error: ${error.message}", Toast.LENGTH_LONG).show()
                    }
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }
    
    private fun toggleSold(item: MarketplaceItem) {
        val newStatus = !item.isSold
        marketplaceManager.markItemAsSold(item.id, newStatus) { result ->
            result.onSuccess {
                val message = if (newStatus) "Marked as sold" else "Marked as available"
                Toast.makeText(context, message, Toast.LENGTH_SHORT).show()
            }.onFailure { error ->
                Toast.makeText(context, "Error: ${error.message}", Toast.LENGTH_LONG).show()
            }
        }
    }
    
    private fun showItemDetails(item: MarketplaceItem) {
        // Open detail fragment/activity
        // TODO: Implement detail view
    }
    
    override fun onDestroyView() {
        super.onDestroyView()
        marketplaceManager.stopWatchingMarketplace()
        _binding = null
    }
}
```

### 4.2 Create layout file `fragment_marketplace.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<androidx.coordinatorlayout.widget.CoordinatorLayout 
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    
    <androidx.recyclerview.widget.RecyclerView
        android:id="@+id/recyclerView"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:clipToPadding="false"
        android:padding="8dp" />
    
    <TextView
        android:id="@+id/emptyView"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_gravity="center"
        android:text="No marketplace items yet"
        android:textSize="16sp"
        android:visibility="gone" />
    
    <com.google.android.material.floatingactionbutton.FloatingActionButton
        android:id="@+id/fabAdd"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_gravity="bottom|end"
        android:layout_margin="16dp"
        android:contentDescription="Add listing"
        app:srcCompat="@android:drawable/ic_input_add" />
    
</androidx.coordinatorlayout.widget.CoordinatorLayout>
```

---

## 🔐 Step 5: Update AndroidManifest.xml (2 min)

Add permissions if not already present:

```xml
<manifest>
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" 
        android:maxSdkVersion="28" />
    
    <!-- For Android 13+ photo picker -->
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
    
    <application>
        <!-- Your existing code -->
    </application>
</manifest>
```

---

## 🧪 Step 6: Test Each Operation (20 min)

### 6.1 Test CREATE
1. Open app and navigate to marketplace
2. Click FAB (+) button
3. Fill in form with test data:
   - Title: "Test Item"
   - Description: "Test description"
   - Price: 50.00
   - Category: Select category
   - Add 1-3 photos
4. Click "Create"
5. **Verify**:
   - Item appears in list immediately (local cache)
   - Upload progress shows
   - Item syncs to Firebase (check Firebase Console)
   - Images appear in Storage (check Storage bucket)

### 6.2 Test UPDATE
1. Long-press an item or click edit icon
2. Change title and price
3. Optionally add/remove photos
4. Save
5. **Verify**:
   - Changes appear immediately
   - Firestore document updated
   - New images uploaded to Storage

### 6.3 Test DELETE
1. Click delete icon on an item you own
2. Confirm deletion
3. **Verify**:
   - Item removed from list immediately
   - Firestore document deleted (Firebase Console)
   - Images deleted from Storage (check all 3 paths)

### 6.4 Test MARK SOLD
1. Click "Mark as Sold" button on item
2. **Verify**:
   - Item shows "SOLD" badge
   - `isSold` = true in Firestore
   - `soldDate` timestamp set
3. Click again to mark available
4. **Verify**: Badge removed, `isSold` = false

### 6.5 Test REAL-TIME SYNC
1. Open app on two devices/emulators
2. Create item on Device A
3. **Verify**: Item appears on Device B within 1-2 seconds
4. Delete item on Device B
5. **Verify**: Item removed on Device A immediately

### 6.6 Test OFFLINE MODE
1. Turn off WiFi/data
2. Create new item
3. **Verify**: Item appears in list (from local cache)
4. Turn on WiFi/data
5. **Verify**: Item uploads automatically and syncs

---

## 🐛 Troubleshooting

### Build Errors
**Error**: `Unresolved reference: MarketplaceManager`
- **Fix**: Make sure package names match your project structure
- **Fix**: Check all imports are correct

**Error**: `Room database schema error`
- **Fix**: Clean project: `Build > Clean Project`
- **Fix**: Rebuild: `Build > Rebuild Project`

**Error**: `kapt not found`
- **Fix**: Add `id 'kotlin-kapt'` to `plugins` section in `app/build.gradle`

### Runtime Errors
**Error**: `FirebaseAuth not initialized`
- **Fix**: Make sure `google-services.json` is in `app/` folder
- **Fix**: Add Firebase initialization in `Application` class

**Error**: `Permission denied: Storage`
- **Fix**: Check Firebase Storage Rules allow authenticated writes
- **Fix**: Update `firebase-storage.rules`:
```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /uploads/{userId}/{allPaths=**} {
      allow write: if request.auth != null && request.auth.uid == userId;
      allow read: if request.auth != null;
    }
    match /marketplace/{itemId}/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }
  }
}
```

**Error**: `Permission denied: Firestore`
- **Fix**: Update Firestore Rules:
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /marketplace/{itemId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update, delete: if request.auth != null && 
        (request.auth.uid == resource.data.ownerId || 
         get(/databases/$(database)/documents/users/$(request.auth.uid)).data.isAdmin == true);
    }
  }
}
```

**Error**: Images not loading
- **Fix**: Check internet permission in manifest
- **Fix**: Verify Glide/Coil is initialized
- **Fix**: Check image URLs in Firestore are valid

---

## ✅ Final Checklist

Before considering implementation complete:

- [ ] All dependencies added and synced
- [ ] All Kotlin files created in correct packages
- [ ] Room database compiles and runs
- [ ] Firebase authentication working
- [ ] Can CREATE new listing with images
- [ ] Can UPDATE existing listing
- [ ] Can DELETE listing (own items only)
- [ ] Can MARK as sold/unsold
- [ ] Real-time sync works between devices
- [ ] Offline mode saves to local cache
- [ ] Images upload with progress indicator
- [ ] Images load from Storage in list view
- [ ] Permission checks work (can't delete others' items)
- [ ] Firebase Console shows correct data structure
- [ ] Storage bucket shows uploaded images
- [ ] Error handling shows user-friendly messages

---

## 🚀 Next Steps (Optional Enhancements)

Once basic CRUD works, consider adding:

1. **Search & Filter**: Add search bar and category filters
2. **Image Optimization**: Compress images before upload
3. **Pagination**: Load items in batches for performance
4. **Push Notifications**: Notify when someone messages about your listing
5. **In-app Messaging**: Chat with seller directly in app
6. **Location-based Search**: Show nearby items first
7. **Favorites**: Let users save favorite listings
8. **Reporting**: Report inappropriate listings

---

## 📞 Need Help?

If you get stuck:

1. Check Firebase Console for data/errors
2. Check Android Logcat for stack traces
3. Verify iOS implementation still works (reference point)
4. Compare Firestore data structure between iOS and Android
5. Test with a fresh install (clear app data)

**Common Issue**: If data doesn't sync between iOS and Android, check that both apps use the same:
- Firebase project
- Collection names ("marketplace")
- Field names (exact spelling/capitalization)
- Data types (String, Double, Boolean, Timestamp)

---

**Estimated Total Time**: 1-2 hours for basic implementation  
**Experience Level**: Intermediate Android developer  
**Prerequisites**: Existing Android app with Firebase already configured

Good luck! 🎉
