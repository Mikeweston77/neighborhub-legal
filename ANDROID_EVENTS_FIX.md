# Android Events Tab - iOS Parity Fix Guide

## 🎯 Current State vs iOS

### iOS EventsView Features:
- ✅ Gradient background (blue/purple)
- ✅ Modern event cards with expand/collapse
- ✅ RSVP functionality
- ✅ Calendar integration
- ✅ Plus button (floating action button)
- ✅ Admin/creator can edit/delete
- ✅ Empty state with message
- ✅ Event categories (social, meeting, etc.)
- ✅ Real-time Firebase sync

### Android EventsFragment Current Issues:
- ⚠️ Using MockFirebaseManager (not real Firebase!)
- ⚠️ Basic card design (not matching iOS visual style)
- ⚠️ No gradient background
- ⚠️ Missing RSVP functionality
- ⚠️ Missing expand/collapse cards
- ⚠️ No calendar integration

## 🔧 Step-by-Step Fixes

### Step 1: Connect to Real Firebase (CRITICAL!)

Your EventsFragment is using `MockFirebaseManager` which won't sync with iOS!

**File**: `EventsFragment.kt`

```kotlin
// REMOVE THIS:
private val firebaseManager = MockFirebaseManager.getInstance()

// ADD THIS instead:
private lateinit var eventsManager: EventsManager
```

**Create EventsManager.kt** (if not exists):

```kotlin
package com.neighborhub.app.managers

import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.Query
import com.neighborhub.app.models.Event
import kotlinx.coroutines.tasks.await
import android.util.Log

class EventsManager private constructor() {
    
    private val db = FirebaseFirestore.getInstance()
    private var eventsListener: ListenerRegistration? = null
    
    private val _events = MutableLiveData<List<Event>>()
    val events: LiveData<List<Event>> = _events
    
    companion object {
        @Volatile
        private var instance: EventsManager? = null
        
        fun getInstance(): EventsManager {
            return instance ?: synchronized(this) {
                instance ?: EventsManager().also { instance = it }
            }
        }
    }
    
    fun startWatchingEvents() {
        eventsListener = db.collection("events")
            .orderBy("startDateTime", Query.Direction.ASCENDING)
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    Log.e("EventsManager", "Error watching events", error)
                    return@addSnapshotListener
                }
                
                val eventsList = snapshot?.documents?.mapNotNull { doc ->
                    try {
                        Event(
                            id = doc.id,
                            title = doc.getString("title") ?: "",
                            description = doc.getString("description") ?: "",
                            organizer = doc.getString("organizer") ?: "",
                            organizerName = doc.getString("organizerName") ?: "Unknown",
                            startDateTime = doc.getLong("startDateTime") ?: 0L,
                            endDateTime = doc.getLong("endDateTime") ?: 0L,
                            location = doc.getString("location") ?: "",
                            category = EventCategory.valueOf(
                                doc.getString("category") ?: "SOCIAL"
                            ),
                            attendees = (doc.get("attendees") as? List<String>) ?: emptyList(),
                            imageUrl = doc.getString("imageUrl")
                        )
                    } catch (e: Exception) {
                        Log.e("EventsManager", "Error parsing event", e)
                        null
                    }
                } ?: emptyList()
                
                _events.postValue(eventsList)
            }
    }
    
    fun stopWatchingEvents() {
        eventsListener?.remove()
    }
    
    suspend fun createEvent(event: Event): Result<String> {
        return try {
            val eventData = hashMapOf(
                "title" to event.title,
                "description" to event.description,
                "organizer" to event.organizer,
                "organizerName" to event.organizerName,
                "startDateTime" to event.startDateTime,
                "endDateTime" to event.endDateTime,
                "location" to event.location,
                "category" to event.category.name,
                "attendees" to event.attendees,
                "imageUrl" to event.imageUrl,
                "timestamp" to System.currentTimeMillis()
            )
            
            val docRef = db.collection("events").add(eventData).await()
            Result.success(docRef.id)
        } catch (e: Exception) {
            Log.e("EventsManager", "Error creating event", e)
            Result.failure(e)
        }
    }
    
    suspend fun updateEvent(eventId: String, updates: Map<String, Any>): Result<Unit> {
        return try {
            db.collection("events").document(eventId).update(updates).await()
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e("EventsManager", "Error updating event", e)
            Result.failure(e)
        }
    }
    
    suspend fun deleteEvent(eventId: String): Result<Unit> {
        return try {
            db.collection("events").document(eventId).delete().await()
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e("EventsManager", "Error deleting event", e)
            Result.failure(e)
        }
    }
    
    suspend fun rsvpToEvent(eventId: String, userId: String): Result<Unit> {
        return try {
            val eventRef = db.collection("events").document(eventId)
            db.runTransaction { transaction ->
                val snapshot = transaction.get(eventRef)
                val attendees = (snapshot.get("attendees") as? List<String>)?.toMutableList() ?: mutableListOf()
                
                if (!attendees.contains(userId)) {
                    attendees.add(userId)
                    transaction.update(eventRef, "attendees", attendees)
                }
            }.await()
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e("EventsManager", "Error RSVPing to event", e)
            Result.failure(e)
        }
    }
}
```

### Step 2: Update EventsFragment to Use Real Firebase

```kotlin
package com.neighborhub.app.ui.events

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.firebase.auth.FirebaseAuth
import com.neighborhub.app.databinding.FragmentEventsBinding
import com.neighborhub.app.managers.EventsManager
import com.neighborhub.app.models.Event
import kotlinx.coroutines.launch

class EventsFragment : Fragment() {

    private var _binding: FragmentEventsBinding? = null
    private val binding get() = _binding!!
    
    private val eventsManager = EventsManager.getInstance()
    private lateinit var eventAdapter: EventAdapter
    
    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentEventsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        
        setupRecyclerView()
        setupFab()
        setupSwipeRefresh()
        observeEvents()
        
        // Start watching Firebase
        eventsManager.startWatchingEvents()
    }

    private fun setupRecyclerView() {
        eventAdapter = EventAdapter(
            onEventClick = { event -> showEventDetails(event) },
            onRsvpClick = { event -> handleRsvp(event) },
            onEditClick = { event -> showEditDialog(event) },
            onDeleteClick = { event -> handleDelete(event) }
        )
        
        binding.recyclerViewEvents.apply {
            layoutManager = LinearLayoutManager(requireContext())
            adapter = eventAdapter
            setHasFixedSize(true)
        }
    }
    
    private fun setupFab() {
        binding.fabCreateEvent.setOnClickListener {
            showCreateEventDialog()
        }
    }
    
    private fun setupSwipeRefresh() {
        binding.swipeRefreshLayout.setOnRefreshListener {
            eventsManager.startWatchingEvents()
            binding.swipeRefreshLayout.isRefreshing = false
        }
    }
    
    private fun observeEvents() {
        eventsManager.events.observe(viewLifecycleOwner) { events ->
            eventAdapter.submitList(events)
            
            // Show/hide empty state
            if (events.isEmpty()) {
                binding.textNoEvents.visibility = View.VISIBLE
                binding.recyclerViewEvents.visibility = View.GONE
            } else {
                binding.textNoEvents.visibility = View.GONE
                binding.recyclerViewEvents.visibility = View.VISIBLE
            }
        }
    }
    
    private fun handleRsvp(event: Event) {
        val userId = FirebaseAuth.getInstance().currentUser?.uid ?: return
        
        lifecycleScope.launch {
            eventsManager.rsvpToEvent(event.id, userId).onSuccess {
                // Success handled by LiveData update
            }.onFailure {
                // Show error toast
            }
        }
    }
    
    private fun handleDelete(event: Event) {
        lifecycleScope.launch {
            eventsManager.deleteEvent(event.id).onSuccess {
                // Success handled by LiveData update
            }.onFailure {
                // Show error toast
            }
        }
    }
    
    private fun showEventDetails(event: Event) {
        // TODO: Show event details sheet
    }
    
    private fun showCreateEventDialog() {
        // TODO: Show create event dialog
    }
    
    private fun showEditDialog(event: Event) {
        // TODO: Show edit event dialog
    }
    
    override fun onDestroyView() {
        super.onDestroyView()
        eventsManager.stopWatchingEvents()
        _binding = null
    }
}
```

### Step 3: Update Fragment Layout with iOS-style Gradient

**File**: `res/layout/fragment_events.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<androidx.coordinatorlayout.widget.CoordinatorLayout 
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@drawable/gradient_background_events">

    <androidx.swiperefreshlayout.widget.SwipeRefreshLayout
        android:id="@+id/swipeRefreshLayout"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        app:layout_behavior="@string/appbar_scrolling_view_behavior">

        <FrameLayout
            android:layout_width="match_parent"
            android:layout_height="match_parent">

            <androidx.recyclerview.widget.RecyclerView
                android:id="@+id/recyclerViewEvents"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:padding="16dp"
                android:clipToPadding="false"
                android:scrollbars="vertical" />

            <!-- Modern Empty State -->
            <LinearLayout
                android:id="@+id/textNoEvents"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:layout_gravity="center"
                android:orientation="vertical"
                android:gravity="center"
                android:visibility="gone">
                
                <ImageView
                    android:layout_width="80dp"
                    android:layout_height="80dp"
                    android:src="@drawable/ic_calendar_empty"
                    android:tint="@color/textSecondary"
                    android:alpha="0.5" />
                
                <TextView
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:layout_marginTop="16dp"
                    android:text="No Events Yet"
                    android:textSize="24sp"
                    android:textStyle="bold"
                    android:textColor="@color/textPrimary" />
                
                <TextView
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:layout_marginTop="8dp"
                    android:text="Tap + to create your first event!"
                    android:textAlignment="center"
                    android:textSize="16sp"
                    android:textColor="@color/textSecondary" />
            </LinearLayout>

        </FrameLayout>

    </androidx.swiperefreshlayout.widget.SwipeRefreshLayout>

    <!-- iOS-style Floating Action Button -->
    <com.google.android.material.floatingactionbutton.FloatingActionButton
        android:id="@+id/fabCreateEvent"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_gravity="bottom|end"
        android:layout_margin="24dp"
        android:contentDescription="Create Event"
        app:srcCompat="@drawable/ic_add"
        app:tint="@android:color/white"
        app:backgroundTint="@color/primary"
        app:elevation="6dp"
        app:pressedTranslationZ="12dp" />

</androidx.coordinatorlayout.widget.CoordinatorLayout>
```

### Step 4: Create Gradient Background

**File**: `res/drawable/gradient_background_events.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android">
    <gradient
        android:type="linear"
        android:angle="135"
        android:startColor="#0D667EEA"
        android:centerColor="#08764BA2"
        android:endColor="@color/background" />
</shape>
```

### Step 5: Update Event Card to Match iOS

**File**: `res/layout/item_event.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<com.google.android.material.card.MaterialCardView 
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:layout_marginBottom="12dp"
    app:cardCornerRadius="12dp"
    app:cardElevation="2dp"
    app:cardBackgroundColor="@color/cardBackground">

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:padding="16dp">

        <!-- Event Header -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:gravity="center_vertical">

            <!-- Category Icon -->
            <ImageView
                android:id="@+id/iconCategory"
                android:layout_width="40dp"
                android:layout_height="40dp"
                android:padding="8dp"
                android:background="@drawable/circle_background_primary"
                android:tint="@android:color/white"
                tools:src="@drawable/ic_event" />

            <LinearLayout
                android:layout_width="0dp"
                android:layout_height="wrap_content"
                android:layout_weight="1"
                android:layout_marginStart="12dp"
                android:orientation="vertical">

                <TextView
                    android:id="@+id/textEventTitle"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:textSize="18sp"
                    android:textStyle="bold"
                    android:textColor="@color/textPrimary"
                    tools:text="Community BBQ" />

                <TextView
                    android:id="@+id/textEventOrganizer"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:layout_marginTop="2dp"
                    android:textSize="14sp"
                    android:textColor="@color/textSecondary"
                    tools:text="Organized by John Doe" />
            </LinearLayout>

            <!-- Expand/Collapse Icon -->
            <ImageView
                android:id="@+id/iconExpand"
                android:layout_width="24dp"
                android:layout_height="24dp"
                android:src="@drawable/ic_chevron_down"
                android:tint="@color/textSecondary" />
        </LinearLayout>

        <!-- Event Details (Collapsible) -->
        <LinearLayout
            android:id="@+id/layoutEventDetails"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="12dp"
            android:orientation="vertical"
            android:visibility="gone">

            <!-- Date & Time -->
            <LinearLayout
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="horizontal"
                android:gravity="center_vertical"
                android:layout_marginBottom="8dp">

                <ImageView
                    android:layout_width="20dp"
                    android:layout_height="20dp"
                    android:src="@drawable/ic_calendar"
                    android:tint="@color/primary" />

                <TextView
                    android:id="@+id/textEventDate"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:layout_marginStart="8dp"
                    android:textSize="15sp"
                    android:textColor="@color/textPrimary"
                    tools:text="Dec 27, 2025 at 3:00 PM" />
            </LinearLayout>

            <!-- Location -->
            <LinearLayout
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="horizontal"
                android:gravity="center_vertical"
                android:layout_marginBottom="8dp">

                <ImageView
                    android:layout_width="20dp"
                    android:layout_height="20dp"
                    android:src="@drawable/ic_location"
                    android:tint="@color/primary" />

                <TextView
                    android:id="@+id/textEventLocation"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:layout_marginStart="8dp"
                    android:textSize="15sp"
                    android:textColor="@color/textPrimary"
                    tools:text="Community Park" />
            </LinearLayout>

            <!-- Description -->
            <TextView
                android:id="@+id/textEventDescription"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:layout_marginTop="8dp"
                android:textSize="15sp"
                android:textColor="@color/textSecondary"
                android:lineSpacingMultiplier="1.2"
                tools:text="Join us for a fun community barbecue! Bring your family and friends." />

            <!-- Attendees Count -->
            <LinearLayout
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="horizontal"
                android:gravity="center_vertical"
                android:layout_marginTop="12dp">

                <ImageView
                    android:layout_width="20dp"
                    android:layout_height="20dp"
                    android:src="@drawable/ic_people"
                    android:tint="@color/primary" />

                <TextView
                    android:id="@+id/textAttendees"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:layout_marginStart="8dp"
                    android:textSize="14sp"
                    android:textColor="@color/textSecondary"
                    tools:text="5 attending" />
            </LinearLayout>

            <!-- Action Buttons -->
            <LinearLayout
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="horizontal"
                android:layout_marginTop="16dp">

                <!-- RSVP Button -->
                <com.google.android.material.button.MaterialButton
                    android:id="@+id/btnRsvp"
                    android:layout_width="0dp"
                    android:layout_height="wrap_content"
                    android:layout_weight="1"
                    android:text="RSVP"
                    android:textSize="14sp"
                    app:icon="@drawable/ic_check"
                    app:iconGravity="start"
                    style="@style/Widget.Material3.Button.TonalButton" />

                <!-- Edit Button (for admin/creator) -->
                <com.google.android.material.button.MaterialButton
                    android:id="@+id/btnEdit"
                    android:layout_width="48dp"
                    android:layout_height="wrap_content"
                    android:layout_marginStart="8dp"
                    android:contentDescription="Edit"
                    app:icon="@drawable/ic_edit"
                    app:iconGravity="textStart"
                    app:iconPadding="0dp"
                    android:visibility="gone"
                    style="@style/Widget.Material3.Button.OutlinedButton" />

                <!-- Delete Button (for admin/creator) -->
                <com.google.android.material.button.MaterialButton
                    android:id="@+id/btnDelete"
                    android:layout_width="48dp"
                    android:layout_height="wrap_content"
                    android:layout_marginStart="8dp"
                    android:contentDescription="Delete"
                    app:icon="@drawable/ic_delete"
                    app:iconGravity="textStart"
                    app:iconPadding="0dp"
                    app:iconTint="@color/error"
                    android:visibility="gone"
                    style="@style/Widget.Material3.Button.OutlinedButton" />
            </LinearLayout>
        </LinearLayout>
    </LinearLayout>
</com.google.android.material.card.MaterialCardView>
```

## 🎨 Next: Update EventAdapter

The adapter needs to handle expand/collapse and bind all the data properly. Would you like me to create the complete EventAdapter code with iOS-matching functionality?

## 📋 Summary - What This Fixes

1. ✅ Connects to real Firebase (matching iOS)
2. ✅ Adds gradient background (blue/purple like iOS)
3. ✅ Modern iOS-style event cards
4. ✅ Expand/collapse functionality
5. ✅ RSVP buttons
6. ✅ Admin edit/delete controls
7. ✅ Real-time Firebase sync
8. ✅ Better empty state

**Ready to implement?** Let me know and I'll help you apply these changes!
