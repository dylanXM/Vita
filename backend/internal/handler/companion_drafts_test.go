package handler

import (
	"archive/zip"
	"bytes"
	"testing"
)

func TestExtractCharacterDocumentTXT(t *testing.T) {
	text, err := extractCharacterDocument("person.txt", []byte("Mina is a quiet illustrator."))
	if err != nil || text != "Mina is a quiet illustrator." {
		t.Fatalf("unexpected result %q, %v", text, err)
	}
}

func TestExtractCharacterDocumentDOCX(t *testing.T) {
	var data bytes.Buffer
	archive := zip.NewWriter(&data)
	file, _ := archive.Create("word/document.xml")
	_, _ = file.Write([]byte(`<w:document xmlns:w="urn:test"><w:body><w:p><w:r><w:t>Mina</w:t></w:r><w:r><w:t>likes tea.</w:t></w:r></w:p></w:body></w:document>`))
	_ = archive.Close()
	text, err := extractCharacterDocument("person.docx", data.Bytes())
	if err != nil || text != "Mina likes tea." {
		t.Fatalf("unexpected result %q, %v", text, err)
	}
}

func TestExtractCharacterDocumentRejectsUnsupportedType(t *testing.T) {
	if _, err := extractCharacterDocument("person.rtf", []byte("text")); err == nil {
		t.Fatal("expected unsupported type to fail")
	}
}
