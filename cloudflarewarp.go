// Package cloudflarewarp Traefik Plugin.
package cloudflarewarp

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"time"

	"github.com/devanoxltd/cloudflarewarp/ips"
)

const (
	xRealIP         = "X-Real-Ip"
	xIsTrusted      = "X-Is-Trusted"
	xForwardedFor   = "X-Forwarded-For"
	xForwardedProto = "X-Forwarded-Proto"
	cfConnectingIP  = "CF-Connecting-IP"
	cfVisitor       = "CF-Visitor"
	tickerInterval  = 1 * time.Minute
)

// Config the plugin configuration.
type Config struct {
	TrustIP             []string `json:"trustip,omitempty"`
	DisableDefaultCFIPs bool     `json:"disableDefault,omitempty"`
	TrustDNSName        string   `json:"trustDnsName,omitempty"`
	ClusterCIDR         []string `json:"clusterCidr,omitempty"`
	Debug               bool     `json:"debug,omitempty"`
}

// TrustResult for Trust IP test result.
type TrustResult struct {
	isFatal  bool
	isError  bool
	trusted  bool
	directIP string
}

// CreateConfig creates the default plugin configuration.
func CreateConfig() *Config {
	return &Config{
		TrustIP:             []string{},
		DisableDefaultCFIPs: false,
		TrustDNSName:        "",
		ClusterCIDR:         []string{},
		Debug:               false,
	}
}

// RealIPOverWriter is a plugin that overwrite true IP.
type RealIPOverWriter struct {
	next       http.Handler
	name       string
	TrustIP    []*net.IPNet
	ticker     *time.Ticker
	tickerQuit chan struct{}
	dnsName    string
	clusterNet []*net.IPNet
	Debug      bool
}

// CFVisitorHeader definition for the header value.
type CFVisitorHeader struct {
	Scheme string `json:"scheme"`
}

// New created a new plugin.
func New(_ context.Context, next http.Handler, config *Config, name string) (http.Handler, error) {
	ipOverWriter := &RealIPOverWriter{
		next: next,
		name: name,
	}

	if config.TrustIP != nil {
		for _, v := range config.TrustIP {
			_, trustip, err := net.ParseCIDR(v)
			if err != nil {
				return nil, err
			}

			ipOverWriter.TrustIP = append(ipOverWriter.TrustIP, trustip)
		}
	}

	ipOverWriter.Debug = config.Debug

	if !config.DisableDefaultCFIPs {
		for _, v := range ips.CFIPs() {
			_, trustip, err := net.ParseCIDR(v)
			if err != nil {
				return nil, err
			}

			ipOverWriter.TrustIP = append(ipOverWriter.TrustIP, trustip)
		}
	}

	if len(config.TrustDNSName) > 0 {
		ipOverWriter.dnsName = config.TrustDNSName
		ipOverWriter.UpdateTrusted(false)
		ipOverWriter.ticker = time.NewTicker(tickerInterval)
		ipOverWriter.tickerQuit = make(chan struct{})
		go func() {
			for {
				select {
				case <-ipOverWriter.ticker.C:
					ipOverWriter.UpdateTrusted(false)
				case <-ipOverWriter.tickerQuit:
					ipOverWriter.ticker.Stop()
					return
				}
			}
		}()
	}

	if len(config.ClusterCIDR) > 0 {
		for _, ip := range config.ClusterCIDR {
			_, clusterNet, err := net.ParseCIDR(ip)
			if err != nil {
				return nil, err
			}
			ipOverWriter.clusterNet = append(ipOverWriter.clusterNet, clusterNet)
		}
	}

	return ipOverWriter, nil
}

// UpdateTrusted Update trusted IPs from DNS.
func (r *RealIPOverWriter) UpdateTrusted(reset bool) {
	if reset {
		r.ticker.Reset(tickerInterval)
	}
	iprecords, err := net.LookupIP(r.dnsName)
	TrustIPNew := []*net.IPNet{}
	if err == nil {
		for _, ip := range iprecords {
			TrustIPNew = append(TrustIPNew, &net.IPNet{IP: ip, Mask: net.CIDRMask(128, 128)}) //nolint:mnd
		}
	}
	r.TrustIP = TrustIPNew
}

func (r *RealIPOverWriter) ServeHTTP(rw http.ResponseWriter, req *http.Request) {
	isCfRequest := len(req.Header.Get(cfConnectingIP)) > 0 //nolint:canonicalheader
	trustResult := r.trust(req.RemoteAddr, isCfRequest)
	req.Header.Set(xIsTrusted, "no") // Initially assume untrusted
	if trustResult.isFatal {
		http.Error(rw, "Unknown source", http.StatusInternalServerError)
		return
	}
	if trustResult.isError {
		http.Error(rw, "Unknown source", http.StatusBadRequest)
		return
	}
	if trustResult.directIP == "" {
		http.Error(rw, "Unknown source", http.StatusUnprocessableEntity)
		return
	}
	debugIP := trustResult.directIP
	if r.Debug {
		if isCfRequest {
			debugIP = req.Header.Get(cfConnectingIP) //nolint:canonicalheader
		} else if trustResult.trusted {
			if len(req.Header.Get(xRealIP)) > 0 {
				debugIP = req.Header.Get(xRealIP)
			} else if len(req.Header.Get(xForwardedFor)) > 0 {
				debugIP = req.Header.Get(xForwardedFor)
			}
		}
		fmt.Printf("DEBUG: Cloudflarewarp: %v isTrusted:%t isCloudflare:%t", debugIP, trustResult.trusted, isCfRequest)
	}
	if trustResult.trusted {
		if req.Header.Get(cfVisitor) != "" { //nolint:canonicalheader
			var cfVisitorValue CFVisitorHeader
			if err := json.Unmarshal([]byte(req.Header.Get(cfVisitor)), &cfVisitorValue); err != nil { //nolint:canonicalheader
				if r.Debug {
					fmt.Printf("DEBUG: Cloudflarewarp: %v Error while parsing CF-Visitor header", debugIP)
				}
				req.Header.Set(xIsTrusted, "no")
				req.Header.Set(xRealIP, trustResult.directIP)
				req.Header.Del(xForwardedFor)
				req.Header.Del(cfVisitor)      //nolint:canonicalheader
				req.Header.Del(cfConnectingIP) //nolint:canonicalheader
				r.next.ServeHTTP(rw, req)
				return
			}
			if r.Debug {
				fmt.Printf("DEBUG: Cloudflarewarp: %v CF-Visitor Scheme:%v", debugIP, cfVisitorValue.Scheme)
			}
			req.Header.Set(xForwardedProto, cfVisitorValue.Scheme)
		}
		if isCfRequest {
			req.Header.Set(xIsTrusted, "yes")
			req.Header.Set(xForwardedFor, req.Header.Get(cfConnectingIP)) //nolint:canonicalheader
			req.Header.Set(xRealIP, req.Header.Get(cfConnectingIP))       //nolint:canonicalheader
		}
	} else {
		req.Header.Set(xIsTrusted, "no")
		req.Header.Set(xRealIP, trustResult.directIP)
		req.Header.Del(xForwardedFor)
		req.Header.Del(cfVisitor)      //nolint:canonicalheader
		req.Header.Del(cfConnectingIP) //nolint:canonicalheader
	}
	r.next.ServeHTTP(rw, req)
}

func (r *RealIPOverWriter) trust(s string, isCF bool) *TrustResult {
	temp, _, err := net.SplitHostPort(s)
	if err != nil {
		return &TrustResult{
			isFatal:  true,
			isError:  true,
			trusted:  false,
			directIP: "",
		}
	}
	ip := net.ParseIP(temp)
	if ip == nil {
		return &TrustResult{
			isFatal:  false,
			isError:  true,
			trusted:  false,
			directIP: "",
		}
	}
	for _, network := range r.TrustIP {
		if network.Contains(ip) {
			return &TrustResult{
				isFatal:  false,
				isError:  false,
				trusted:  true,
				directIP: ip.String(),
			}
		} else if isCF && r.inCluster(ip) {
			r.UpdateTrusted(true)
			if network.Contains(ip) {
				return &TrustResult{
					isFatal:  false,
					isError:  false,
					trusted:  true,
					directIP: ip.String(),
				}
			}
		}
	}
	return &TrustResult{
		isFatal:  false,
		isError:  false,
		trusted:  false,
		directIP: ip.String(),
	}
}

func (r *RealIPOverWriter) inCluster(ip net.IP) bool {
	for _, network := range r.clusterNet {
		if network.Contains(ip) {
			return true
		}
	}
	return false
}
