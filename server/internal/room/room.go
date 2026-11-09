// Package room indexes which sessions subscribe to which game map.
package room

import "github.com/AurelienBaraquin/pif-online/server/internal/session"

// Index maps a map id to its subscribers. It is not safe for concurrent use.
type Index struct {
	subscribers map[int]map[session.ID]struct{}
}

// NewIndex returns an empty index.
func NewIndex() *Index {
	return &Index{subscribers: make(map[int]map[session.ID]struct{})}
}

// Subscribe adds a session to a map.
func (i *Index) Subscribe(mapID int, id session.ID) {
	members, exists := i.subscribers[mapID]
	if !exists {
		members = make(map[session.ID]struct{})
		i.subscribers[mapID] = members
	}
	members[id] = struct{}{}
}

// Unsubscribe removes a session from a map and frees the map when empty.
func (i *Index) Unsubscribe(mapID int, id session.ID) {
	members, exists := i.subscribers[mapID]
	if !exists {
		return
	}
	delete(members, id)
	if len(members) == 0 {
		delete(i.subscribers, mapID)
	}
}

// Subscribers returns the sessions subscribed to any of the given maps,
// without duplicates.
func (i *Index) Subscribers(mapIDs ...int) []session.ID {
	seen := make(map[session.ID]struct{})
	result := make([]session.ID, 0)
	for _, mapID := range mapIDs {
		for id := range i.subscribers[mapID] {
			if _, duplicate := seen[id]; duplicate {
				continue
			}
			seen[id] = struct{}{}
			result = append(result, id)
		}
	}
	return result
}

// MapCount returns how many maps have at least one subscriber.
func (i *Index) MapCount() int {
	return len(i.subscribers)
}
