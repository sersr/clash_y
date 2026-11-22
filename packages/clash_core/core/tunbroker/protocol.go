package tunbroker

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/netip"
	"strings"
)

const maxMessageSize = 64 * 1024

func writeRequest(writer io.Writer, request Request) error {
	return writeMessage(writer, request)
}

func writeResponse(writer io.Writer, response Response) error {
	return writeMessage(writer, response)
}

func writeMessage(writer io.Writer, value any) error {
	payload, err := json.Marshal(value)
	if err != nil {
		return fmt.Errorf("encode TUN helper message: %w", err)
	}
	payload = append(payload, '\n')
	for len(payload) > 0 {
		n, err := writer.Write(payload)
		if err != nil {
			return err
		}
		if n == 0 {
			return errors.New("TUN helper message write made no progress")
		}
		payload = payload[n:]
	}
	return nil
}

func readRequest(reader io.Reader) (Request, error) {
	line, err := readMessage(reader)
	if err != nil {
		return Request{}, err
	}
	var request Request
	if err := json.Unmarshal(line, &request); err != nil {
		return Request{}, fmt.Errorf("decode TUN helper request: %w", err)
	}
	return request, nil
}

func readResponse(reader io.Reader) (Response, error) {
	line, err := readMessage(reader)
	if err != nil {
		return Response{}, err
	}
	var response Response
	if err := json.Unmarshal(line, &response); err != nil {
		return Response{}, fmt.Errorf("decode TUN helper response: %w", err)
	}
	return response, nil
}

func readMessage(reader io.Reader) ([]byte, error) {
	buffered, ok := reader.(*bufio.Reader)
	if !ok {
		buffered = bufio.NewReader(reader)
	}
	line, err := buffered.ReadString('\n')
	if err != nil {
		return nil, err
	}
	if len(line) > maxMessageSize {
		return nil, errors.New("TUN helper message is too large")
	}
	return []byte(strings.TrimSpace(line)), nil
}

func validateConfig(config Config) error {
	if config.MTU != 0 && (config.MTU < 1280 || config.MTU > 65535) {
		return fmt.Errorf("invalid TUN MTU: %d", config.MTU)
	}
	if len(config.Inet4Address) == 0 && len(config.Inet6Address) == 0 {
		return errors.New("TUN helper requires at least one interface address")
	}
	for _, value := range config.Inet4Address {
		prefix, err := netip.ParsePrefix(value)
		if err != nil || !prefix.Addr().Is4() {
			return fmt.Errorf("invalid TUN IPv4 address %q", value)
		}
	}
	for _, value := range config.Inet6Address {
		prefix, err := netip.ParsePrefix(value)
		if err != nil || !prefix.Addr().Is6() {
			return fmt.Errorf("invalid TUN IPv6 address %q", value)
		}
	}
	if _, err := RoutePrefixes(config); err != nil {
		return err
	}
	return nil
}

func sameInterfaceConfig(left, right Config) bool {
	if left.MTU != right.MTU ||
		len(left.Inet4Address) != len(right.Inet4Address) ||
		len(left.Inet6Address) != len(right.Inet6Address) {
		return false
	}
	for index := range left.Inet4Address {
		if left.Inet4Address[index] != right.Inet4Address[index] {
			return false
		}
	}
	for index := range left.Inet6Address {
		if left.Inet6Address[index] != right.Inet6Address[index] {
			return false
		}
	}
	return true
}
