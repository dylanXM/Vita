package encounterart

import (
 "embed"
 "fmt"
)

// Files ships the original four generated character covers with Backend.
//go:embed images/*.png
var Files embed.FS

func Read(name string) ([]byte,error) {
 switch name { case "east-man.png","west-man.png","east-woman.png","west-woman.png":
  return Files.ReadFile("images/"+name)
 default: return nil,fmt.Errorf("unknown encounter artwork") }
}
