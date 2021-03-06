package main

import (
	"fmt"
	"io/ioutil"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"testing/iotest"

	"golang.org/x/net/context"
	storage "google.golang.org/api/storage/v1"
)

type myHandler struct {
	location string
	r        *http.Request
	body     []byte
	err      error
}

func (h *myHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	h.r = r
	if h.location != "" {
		w.Header().Set("Location", h.location)
	}
	h.body, h.err = ioutil.ReadAll(r.Body)
	fmt.Fprintf(w, "{}")
}

func TestMedia(t *testing.T) {
	handler := &myHandler{}
	server := httptest.NewServer(handler)
	defer server.Close()

	client := &http.Client{}
	s, err := storage.New(client)
	if err != nil {
		t.Fatalf("unable to create service: %v", err)
	}
	s.BasePath = server.URL

	const body = "fake media data"
	f := strings.NewReader(body)
	o := &storage.Object{
		Bucket:          "mybucket",
		Name:            "filename",
		ContentType:     "plain/text",
		ContentEncoding: "utf-8",
		ContentLanguage: "en",
	}
	_, err = s.Objects.Insert("mybucket", o).Media(f).Do()
	if err != nil {
		t.Fatalf("unable to insert object: %v", err)
	}
	g := handler.r
	if w := "POST"; g.Method != w {
		t.Errorf("Method = %q; want %q", g.Method, w)
	}
	if w := "HTTP/1.1"; g.Proto != w {
		t.Errorf("Proto = %q; want %q", g.Proto, w)
	}
	if w := 1; g.ProtoMajor != w {
		t.Errorf("ProtoMajor = %v; want %v", g.ProtoMajor, w)
	}
	if w := 1; g.ProtoMinor != w {
		t.Errorf("ProtoMinor = %v; want %v", g.ProtoMinor, w)
	}
	if w, k := "google-api-go-client/0.5", "User-Agent"; len(g.Header[k]) != 1 || g.Header[k][0] != w {
		t.Errorf("header %q = %#v; want %q", k, g.Header[k], w)
	}
	if w, k := "multipart/related; boundary=", "Content-Type"; len(g.Header[k]) != 1 || !strings.HasPrefix(g.Header[k][0], w) {
		t.Errorf("header %q = %#v; want %q", k, g.Header[k], w)
	}
	if w, k := "gzip", "Accept-Encoding"; len(g.Header[k]) != 1 || g.Header[k][0] != w {
		t.Errorf("header %q = %#v; want %q", k, g.Header[k], w)
	}
	if w := int64(-1); g.ContentLength != w {
		t.Errorf("ContentLength = %v; want %v", g.ContentLength, w)
	}
	if w := "chunked"; len(g.TransferEncoding) != 1 || g.TransferEncoding[0] != w {
		t.Errorf("TransferEncoding = %#v; want %q", g.TransferEncoding, w)
	}
	if w := strings.TrimPrefix(s.BasePath, "http://"); g.Host != w {
		t.Errorf("Host = %q; want %q", g.Host, w)
	}
	if g.Form != nil {
		t.Errorf("Form = %#v; want nil", g.Form)
	}
	if g.PostForm != nil {
		t.Errorf("PostForm = %#v; want nil", g.PostForm)
	}
	if g.MultipartForm != nil {
		t.Errorf("MultipartForm = %#v; want nil", g.MultipartForm)
	}
	if w := s.BasePath + "/b/mybucket/o?alt=json&uploadType=multipart"; g.RequestURI != w {
		t.Errorf("RequestURI = %q; want %q", g.RequestURI, w)
	}
	if w := "\r\n\r\n" + body + "\r\n"; !strings.Contains(string(handler.body), w) {
		t.Errorf("Body = %q, want substring %q", handler.body, w)
	}
	if handler.err != nil {
		t.Errorf("handler err = %v, want nil", handler.err)
	}
}

func TestResumableMedia(t *testing.T) {
	handler := &myHandler{}
	server := httptest.NewServer(handler)
	defer server.Close()

	handler.location = server.URL
	client := &http.Client{}
	s, err := storage.New(client)
	if err != nil {
		t.Fatalf("unable to create service: %v", err)
	}
	s.BasePath = server.URL

	const data = "fake resumable media data"
	f := strings.NewReader(data)
	o := &storage.Object{
		Bucket:          "mybucket",
		Name:            "filename",
		ContentType:     "plain/text",
		ContentEncoding: "utf-8",
		ContentLanguage: "en",
	}
	_, err = s.Objects.Insert("mybucket", o).Name("filename").ResumableMedia(context.Background(), f, int64(len(data)), "text/plain").Do()
	if err != nil {
		t.Fatalf("unable to insert object: %v", err)
	}
	g := handler.r
	if w := "POST"; g.Method != w {
		t.Errorf("Method = %q; want %q", g.Method, w)
	}
	if w := "HTTP/1.1"; g.Proto != w {
		t.Errorf("Proto = %q; want %q", g.Proto, w)
	}
	if w := 1; g.ProtoMajor != w {
		t.Errorf("ProtoMajor = %v; want %v", g.ProtoMajor, w)
	}
	if w := 1; g.ProtoMinor != w {
		t.Errorf("ProtoMinor = %v; want %v", g.ProtoMinor, w)
	}
	if w, k := "google-api-go-client/0.5", "User-Agent"; len(g.Header[k]) != 1 || g.Header[k][0] != w {
		t.Errorf("header %q = %#v; want %q", k, g.Header[k], w)
	}
	if k := "Content-Type"; len(g.Header[k]) != 0 {
		t.Errorf("header %q = %#v; want nil", k, g.Header[k])
	}
	if w, k := "gzip", "Accept-Encoding"; len(g.Header[k]) != 1 || g.Header[k][0] != w {
		t.Errorf("header %q = %#v; want %q", k, g.Header[k], w)
	}
	if w := int64(0); g.ContentLength != w {
		t.Errorf("ContentLength = %v; want %v", g.ContentLength, w)
	}
	if len(g.TransferEncoding) != 0 {
		t.Errorf("TransferEncoding = %#v; want nil", g.TransferEncoding)
	}
	if g.Form != nil {
		t.Errorf("Form = %#v; want nil", g.Form)
	}
	if g.PostForm != nil {
		t.Errorf("PostForm = %#v; want nil", g.PostForm)
	}
	if g.MultipartForm != nil {
		t.Errorf("MultipartForm = %#v; want nil", g.MultipartForm)
	}
	if handler.err != nil {
		t.Errorf("handler err = %v, want nil", handler.err)
	}
}

func TestNoMedia(t *testing.T) {
	handler := &myHandler{}
	server := httptest.NewServer(handler)
	defer server.Close()

	client := &http.Client{}
	s, err := storage.New(client)
	if err != nil {
		t.Fatalf("unable to create service: %v", err)
	}
	s.BasePath = server.URL

	o := &storage.Object{
		Bucket:          "mybucket",
		Name:            "filename",
		ContentType:     "plain/text",
		ContentEncoding: "utf-8",
		ContentLanguage: "en",
	}
	_, err = s.Objects.Insert("mybucket", o).Do()
	if err != nil {
		t.Fatalf("unable to insert object: %v", err)
	}
	g := handler.r
	if w := "POST"; g.Method != w {
		t.Errorf("Method = %q; want %q", g.Method, w)
	}
	if w := "HTTP/1.1"; g.Proto != w {
		t.Errorf("Proto = %q; want %q", g.Proto, w)
	}
	if w := 1; g.ProtoMajor != w {
		t.Errorf("ProtoMajor = %v; want %v", g.ProtoMajor, w)
	}
	if w := 1; g.ProtoMinor != w {
		t.Errorf("ProtoMinor = %v; want %v", g.ProtoMinor, w)
	}
	if w, k := "google-api-go-client/0.5", "User-Agent"; len(g.Header[k]) != 1 || g.Header[k][0] != w {
		t.Errorf("header %q = %#v; want %q", k, g.Header[k], w)
	}
	if w, k := "application/json", "Content-Type"; len(g.Header[k]) != 1 || g.Header[k][0] != w {
		t.Errorf("header %q = %#v; want %q", k, g.Header[k], w)
	}
	if w, k := "gzip", "Accept-Encoding"; len(g.Header[k]) != 1 || g.Header[k][0] != w {
		t.Errorf("header %q = %#v; want %q", k, g.Header[k], w)
	}
	if w := int64(116); g.ContentLength != w {
		t.Errorf("ContentLength = %v; want %v", g.ContentLength, w)
	}
	if len(g.TransferEncoding) != 0 {
		t.Errorf("TransferEncoding = %#v; want []string{}", g.TransferEncoding)
	}
	if w := strings.TrimPrefix(s.BasePath, "http://"); g.Host != w {
		t.Errorf("Host = %q; want %q", g.Host, w)
	}
	if g.Form != nil {
		t.Errorf("Form = %#v; want nil", g.Form)
	}
	if g.PostForm != nil {
		t.Errorf("PostForm = %#v; want nil", g.PostForm)
	}
	if g.MultipartForm != nil {
		t.Errorf("MultipartForm = %#v; want nil", g.MultipartForm)
	}
	if w := s.BasePath + "/b/mybucket/o?alt=json"; g.RequestURI != w {
		t.Errorf("RequestURI = %q; want %q", g.RequestURI, w)
	}
	if w := `{"bucket":"mybucket","contentEncoding":"utf-8","contentLanguage":"en","contentType":"plain/text","name":"filename"}` + "\n"; string(handler.body) != w {
		t.Errorf("Body = %q, want %q", handler.body, w)
	}
	if handler.err != nil {
		t.Errorf("handler err = %v, want nil", handler.err)
	}
}

func TestMediaErrHandling(t *testing.T) {
	handler := &myHandler{}
	server := httptest.NewServer(handler)
	defer server.Close()

	client := &http.Client{}
	s, err := storage.New(client)
	if err != nil {
		t.Fatalf("unable to create service: %v", err)
	}
	s.BasePath = server.URL

	const body = "fake media data"
	f := strings.NewReader(body)
	// The combination of TimeoutReader and OneByteReader causes the first byte to
	// be successfully delivered, but then a timeout error is reported.  This
	// allows us to test the goroutine within the getMediaType function.
	r := iotest.TimeoutReader(iotest.OneByteReader(f))
	o := &storage.Object{
		Bucket:          "mybucket",
		Name:            "filename",
		ContentType:     "plain/text",
		ContentEncoding: "utf-8",
		ContentLanguage: "en",
	}
	_, err = s.Objects.Insert("mybucket", o).Media(r).Do()
	if err == nil || !strings.Contains(err.Error(), "timeout") {
		t.Errorf("expected timeout error, got %v", err)
	}
	if handler.err != nil {
		t.Errorf("handler err = %v, want nil", handler.err)
	}
}

func TestUserAgent(t *testing.T) {
	handler := &myHandler{}
	server := httptest.NewServer(handler)
	defer server.Close()

	client := &http.Client{}
	s, err := storage.New(client)
	if err != nil {
		t.Fatalf("unable to create service: %v", err)
	}
	s.BasePath = server.URL
	s.UserAgent = "myagent/1.0"

	f := strings.NewReader("fake media data")
	o := &storage.Object{
		Bucket:          "mybucket",
		Name:            "filename",
		ContentType:     "plain/text",
		ContentEncoding: "utf-8",
		ContentLanguage: "en",
	}
	_, err = s.Objects.Insert("mybucket", o).Media(f).Do()
	if err != nil {
		t.Fatalf("unable to insert object: %v", err)
	}
	g := handler.r
	if w, k := "google-api-go-client/0.5 myagent/1.0", "User-Agent"; len(g.Header[k]) != 1 || g.Header[k][0] != w {
		t.Errorf("header %q = %#v; want %q", k, g.Header[k], w)
	}
}
