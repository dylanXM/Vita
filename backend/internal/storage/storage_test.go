package storage

import "testing"

func TestPresignedURLDoesNotDuplicateObjectKey(t *testing.T) {
	url, err := (&Storage{}).PresignedURL("vita-media", "companions/photo.png", 300)
	if err != nil {
		t.Fatal(err)
	}
	if url != "https://vita-media.s3.amazonaws.com/companions/photo.png" {
		t.Fatalf("url = %q", url)
	}
}
