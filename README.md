# easy_upnp
A super simple UPnP control point client for Ruby

## Installing

easy_upnp is available on [Rubygems](https://rubygems.org). You can install it with:

```
$ gem install easy_upnp
```

You can also add it to your Gemfile:

```
gem 'easy_upnp'
```

## Example usage

#### Find devices with SSDP

[Simple Service Discovery Protocol](http://upnp.org/specs/arch/UPnP-arch-DeviceArchitecture-v1.1.pdf) (SSDP) is a simple UDP protocol used to discover services on a network. It's the entry point to create control points in easy_upnp.

The `search` method takes one argument -- the "search target". This controls a header sent in the SSDP packet which affects the devices that respond to the search query. You can use `'ssdp:all'` to specify that all devices should respond.

```ruby
require 'easy_upnp/ssdp_searcher'

searcher = EasyUpnp::SsdpSearcher.new 
devices = searcher.search 'ssdp:all'
```

This will return a list of `EasyUpnp::UpnpDevice` objects. You'll use these to interact with devices on your network.

#### Interacting with a specific device

Once you have a `EasyUpnp::UpnpDevice`, you can start interacting with the services it advertizes. To get a list of all services a device supports:

```ruby
device = devices.first
device.all_services
# => ["urn:schemas-upnp-org:service:ContentDirectory:1", "urn:schemas-upnp-org:service:ConnectionManager:1", "urn:microsoft.com:service:X_MS_MediaReceiverRegistrar:1"]
```

You can then create a service client and make calls to the service:

```ruby
service = device.service 'urn:schemas-upnp-org:service:ContentDirectory:1'

service.service_methods
# => ["GetSearchCapabilities", "GetSortCapabilities", "GetSystemUpdateID", "Browse", "Search"]

service.GetSystemUpdateID
# => {:Id=>"207"}
```
