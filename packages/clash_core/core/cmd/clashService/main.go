// Command clashService is the desktop daemon behind Clashy. The service lives
// in internal/clashservice so the mobile tunnel can import the same code.
package main

import "mihomo-so/internal/clashservice"

func main() { clashservice.Run() }
