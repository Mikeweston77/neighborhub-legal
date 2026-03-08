# Poll Crash Fix - Third Option Voting Issue

## Problem
When adding a 3rd option to a poll and then voting on it, the app crashes with an index out of bounds error.

## Root Cause
The crash occurs when the `votes` array and `options` array become desynchronized in length. This can happen in several scenarios:

1. **Firebase Data Corruption**: If poll data in Firestore has mismatched array lengths
2. **Race Conditions**: When polls are updated while users are voting
3. **Migration Issues**: When existing polls are loaded that were created with different array lengths

The crash specifically occurs in:
- `voteStatsView(for idx: Int)` when accessing `poll.votes[idx]`
- Vote button actions when trying to vote on an invalid option index

## Solution

### 1. Firebase Manager Fix (`FirebaseManager.swift`)
Added array length synchronization when parsing polls from Firestore:

```swift
// Ensure votes array matches options array length to prevent crashes
while votes.count < options.count {
    votes.append(0)
}
while votes.count > options.count {
    votes.removeLast()
}
```

### 2. UI Safety Checks (`HomeView.swift`)

#### A. Safe Vote Stats Display
```swift
private func voteStatsView(for idx: Int) -> some View {
    VStack(alignment: .trailing, spacing: 2) {
        // Safely access votes array with bounds checking
        let voteCount = idx < poll.votes.count ? poll.votes[idx] : 0
        // ... rest of function
    }
}
```

#### B. Safe Voting Action
```swift
Button(action: {
    // Only call onVote if user hasn't voted yet and not currently voting
    // Also ensure the index is valid for the votes array
    if poll.userVote == nil && !isVotingInProgress && idx < poll.votes.count {
        onVote(idx)
    }
})
```

#### C. Safe Poll Loading
Added synchronization when converting Firebase DTO to local Poll:

```swift
// Ensure votes array matches options array length to prevent crashes
var safeVotes = dto.votes
while safeVotes.count < dto.options.count {
    safeVotes.append(0)
}
while safeVotes.count > dto.options.count {
    safeVotes.removeLast()
}
```

## Technical Details

### Where the Crash Occurred
1. **Display Phase**: When showing vote statistics via `voteStatsView(for:)`
2. **Voting Phase**: When user taps vote button and votes array is shorter than options
3. **Loading Phase**: When Firebase returns poll data with mismatched arrays

### Prevention Strategy
- **Defensive Programming**: All array accesses now use bounds checking
- **Data Sanitization**: Arrays are synchronized at the data layer (Firebase) and UI layer
- **Graceful Degradation**: If vote count is missing, defaults to 0 instead of crashing

## Files Modified

1. **`/NeighborHub/Managers/FirebaseManager.swift`**
   - Added array synchronization in `pollDTO(from:)` function
   - Ensures votes array matches options array length

2. **`/NeighborHub/Views/HomeView.swift`**
   - Added bounds checking in `voteStatsView(for:)`
   - Added validation in vote button action
   - Added safety check when loading polls from Firebase

## Testing Recommendations

1. **Create a poll with 2 options** → Add 3rd option → Vote → Verify no crash
2. **Test with existing polls** → Ensure they still work correctly
3. **Test voting on each option** → Verify statistics display correctly
4. **Test Firebase sync** → Ensure votes persist across app restarts

## Prevention for Future

- Always ensure that any array operations between `options` and `votes` maintain length synchronization
- Use defensive programming practices when accessing arrays by index
- Consider using safer data structures or validation layers for poll data

The fix ensures that polls work reliably even when data inconsistencies occur, providing a better user experience and preventing crashes.