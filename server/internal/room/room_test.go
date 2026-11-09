package room

import (
	"sort"
	"testing"

	"github.com/AurelienBaraquin/pif-online/server/internal/session"
)

func sorted(ids []session.ID) []session.ID {
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })
	return ids
}

func TestSubscribersAreDeduplicatedAcrossMaps(t *testing.T) {
	index := NewIndex()
	index.Subscribe(1, 10)
	index.Subscribe(2, 10)
	index.Subscribe(2, 20)

	got := sorted(index.Subscribers(1, 2))

	if len(got) != 2 || got[0] != 10 || got[1] != 20 {
		t.Fatalf("got %v", got)
	}
}

func TestUnsubscribeFreesEmptyMaps(t *testing.T) {
	index := NewIndex()
	index.Subscribe(1, 10)

	index.Unsubscribe(1, 10)
	index.Unsubscribe(1, 10)
	index.Unsubscribe(99, 10)

	if index.MapCount() != 0 {
		t.Fatalf("map count = %d", index.MapCount())
	}
}
