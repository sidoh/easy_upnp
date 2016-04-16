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

## Static client construction

After you've constructed a client (`DeviceControlPoint`), you probably don't want to have to use SSDP to construct it again the next time you use it. `DeviceControlPoint` is equipped with `#to_params` and `#from_params` methods to make this easy.

Say you have a client called `client`. To dump it into a hash, do the following:

```ruby
params = client.to_params
#=> {:urn=>"urn:schemas-upnp-org:service:ContentDirectory:1", :service_endpoint=>"http://10.133.8.11:8200/ctl/ContentDir", :definition=>"<?xml version=\"1.0\"?>\r\n<scpd xmlns=\"urn:schemas-upnp-org:service-1-0\">( ... clipped ... )</scpd>", :options=>{}}
```

We can then reconstruct a client from these params and use it normally:

```ruby
client = EasyUpnp::DeviceControlPoint.from_params(params)
client.GetSystemUpdateID
=> {:Id=>"258"}
```

## Logging

By default, logs will be printed to `$stdout` at the `:error` level. To change this behavior, you can use the following options when constructing a control point:

```ruby
service = client.service(
  'urn:schemas-upnp-org:service:ContentDirectory:1', 
  log_enabled: true, 
  log_level: :info
)

service = client.service('urn:schemas-upnp-org:service:ContentDirectory:1') do |s|
  s.log_enabled = true
  s.log_level = :debug
end
```

## Validation

Clients can validate the arguments passed to its methods. By default, this behavior is disabled. You can enable it when initializing a client:

```ruby
client = device.service('urn:schemas-upnp-org:service:ContentDirectory:1') do |o|
  o.validate_arguments = true
end
```

This enables type checking in addition to whatever validation information is available in the UPnP service's definition. For example:

```ruby
client.GetVolume(InstanceID: '0', Channel: 'Master')
#: ArgumentError: Invalid value for argument InstanceID: 0 is the wrong type. Should be one of: [Integer]
client.GetVolume(InstanceID: 0, Channel: 'Master2')
#: ArgumentError: Invalid value for argument Channel: Master2 is not in list of allowed values: ["Master"]
client.GetVolume(InstanceID: 0, Channel: 'Master')
#=> {:CurrentVolume=>"32"}
```

It's also possible to retrieve information about arguments:

```ruby
client.method_args(:SetVolume)
#=> [:InstanceID, :Channel, :DesiredVolume]
validator = client.arg_validator(:SetVolume, :DesiredVolume)
validator.required_class
#=> Integer
validator.valid_range
#=> #<Enumerator: 0..100:step(1)>
validator.valid_range.max
#=> 100
validator.validate(32)
#=> true
validator.validate(101)
#: ArgumentError: 101 is not in allowed range of values: #<Enumerator: 0..100:step(1)>

validator = client.arg_validator(:SetVolume, :Channel)
validator.allowed_values
#=> ["Master"]
```
