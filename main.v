import net.http
import sync
import time
import json
import os

fn with_key(key string) fn (Collector) ?Collector {
	return fn [key] (c Collector) ?Collector {
		return Collector{
			api_key: key
			bridge_address: c.bridge_address
		}
	}
}

fn with_internal_ip(ip string) fn (Collector) ?Collector {
	return fn [ip] (c Collector) ?Collector {
		return Collector{
			api_key: c.api_key
			bridge_address: ip
		}
	}
}

fn main() {
        if os.args.len > 3 {
		eprintln('no API key provided')
		return
	}

	mut c := new_collector(with_key(os.args[1]), with_internal_ip(os.args[2])) or {
		eprintln(err)
		return
	}

	if !c.is_authenticated() {
		bridges := c.discover() or {
			eprintln(err)
			return
		}

		println('bridge count: $bridges.len')
		if bridges.len == 0 {
			eprintln('no bridge discovered')
			return
		}
	}

	mut wg := sync.new_waitgroup()
	wg.add(2)

	go collect_lights(mut wg, c)
	go collect_groups(mut wg)

	wg.wait()
}

fn collect_lights(mut wg sync.WaitGroup, c Collector) {
	defer {
		wg.done()
	}

	println('collecting lights...')

	lights := c.get_lights() or {
		eprintln(err)
		return
	}

        for light in lights {
                println(light)
        }

	return
}

fn collect_groups(mut wg sync.WaitGroup) {
	defer {
		wg.done()
	}

	println('collecting groups...')

	return
}

struct Collector {
	timeout time.Time
mut:
	api_key        string
	bridge_address string
}

fn new_collector(options ...fn (Collector) ?Collector) ?Collector {
	mut c := Collector{}

	for option in options {
		c = option(c) or { return err }
	}

	return c
}

struct Bridge {
	id                string
	internalipaddress string
	port              int
}

struct Light {
        state State
        swupdate SoftwareUpdate
        // type string
        name string
        modelid string
        manufacturername string
        productname string
        config Config
        capabilities Capabilities
        swversion string
        swconfigid string
        productid string
}

struct SoftwareUpdate {
        state string
        lastinstall string
}

struct Config {
        archetype string
        function string
        direction string
        startup Startup
}

struct Startup {
        mode string
        configured bool
}

struct Capabilities {
        certified bool
        control ControlCapabilities
        streaming StreamingCapabilities
}

struct ControlCapabilities{
        mindimlevel int
        maxlumen int
}

struct StreamingCapabilities {
        renderer bool
        proxy bool
}

struct State {
        on bool
        bri int
        alert string
        mode string
        reachable bool
}

fn (c Collector) discover() ?[]Bridge {
	res := http.get('https://discovery.meethue.com') or { return err }

	match true {
		res.status_code == 200 {
			return json.decode([]Bridge, res.text)
		}
		res.status_code < 500 {
			return []Bridge{}
		}
		else {
			return error('failed to fetch bridge: '+res.status_msg)
		}
	}
}

fn (mut c Collector) set_key(key string) {
	c.api_key = key
}

fn (c Collector) get_lights() ?[]Light {
        println(c.bridge_address)

	res := http.get("http://"+c.bridge_address+"/api/"+c.api_key+"/lights") or {
                return err
        }

        match true {
                res.status_code == 200 {
                        println(res.status_code)
                        results := json.decode(map[string]Light, res.text) or {
                                return error('failed to decode result')
                        }
                        println(results.len)
                        mut lights := []Light{}
                        for _, light in results {
                                lights.prepend(light)
                        }

                        return lights
                }
                res.status_code < 500 {
                        return []Light{}
                }
                else {
                        return error('failed to fetch lights: '+res.status_msg)
                }
        }

}

fn (c Collector) is_authenticated() bool {
	if c.api_key == '' {
		return false
	}

	if c.bridge_address == '' {
		return false
	}

	return true
}
