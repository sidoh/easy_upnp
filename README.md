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

## Events

easy_upnp allows you to subscribe to events. UPnP events are supported by registering HTTP callbacks with services. You can read more about the specifics in Section 4 of the [UPnP Device Architecture document](http://upnp.org/specs/arch/UPnP-arch-DeviceArchitecture-v1.1.pdf). Using this you could, for example, receive events when the volume or mute state changes on your UPnP-enabled TV. You might see something like this HTTP request, for example:

```
NOTIFY / HTTP/1.1
Host: 192.168.1.100:8888
Date: Sun, 17 Apr 2016 07:40:01 GMT
User-Agent: UPnP/1.0
Content-Type: text/xml; charset="utf-8"
Content-Length: 479
NT: upnp:event
NTS: upnp:propchange
SID: uuid:9742fed0-046f-11e6-8000-fcf1524b4f9c
SEQ: 0

<?xml version="1.0"?><e:propertyset xmlns:e="urn:schemas-upnp-org:event-1-0"><e:property><LastChange>&lt;Event xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/RCS/&quot;&gt;
  &lt;InstanceID val=&quot;0&quot;&gt;
    &lt;PresetNameList val=&quot;FactoryDefaults&quot;/&gt;
    &lt;Mute val=&quot;0&quot; channel=&quot;Master&quot;/&gt;
    &lt;Volume val=&quot;34&quot; channel=&quot;Master&quot;/&gt;
  &lt;/InstanceID&gt;
&lt;/Event&gt;
</LastChange></e:property></e:propertyset>
```

There are two ways you can subscribe to events with easy_upnp:

1. Registering a custom HTTP endpoint.
2. Providing a callback `lambda` or `Proc` which is called each time an event is fired.

In the case of (2), easy_upnp behind the scenes starts a WEBrick HTTP server, which calls the provided callback whenever it receives an HTTP `NOTIFY` request. 

#### Calling URLs

To add a URL to be called on events:

```ruby
# Registers the provided URL with the service. If everything works appropriately, this
# URL will be called with HTTP NOTIFY requests from the service.
manager = service.add_event_callback('http://myserver/path/to/callback')

# The object that's returned allows you to manage the event subscription. To 
# cancel the subscription, for example:
manager.unsubscribe

# You can also start the subscription after unsubscribing:
manager.subscribe

# Or get the subscription identifier:
manager.subscription_id
#=> "uuid:6ef254f0-04d1-11e6-8000-fcf1524b4f9c"
```

You can also construct a manager that attempts to manage an existing subscription:

```ruby
manager = service.add_event_callback('http://myserver/path/to/callback') do |c|
  c.existing_sid = 'uuid:6ef254f0-04d1-11e6-8000-fcf1524b4f9c'
end
```

#### Calling ruby code

If you don't want to have to set up an HTTP endpoint to listen to events, you can have easy_upnp do it for you. The `on_event` starts an internal HTTP server on an ephemeral port behind the scenes and triggers the provided callback each time a request is recieved. 

```ruby
# Parse and print the XML body of the request
callback = ->(request) { puts Nokogiri::XML(request.body).to_xml }
manager = service.on_event(callback)

# End the subscription and shut down the internal HTTP server
manager.unsubscribe

# This will start a new HTTP server and start a new subscription
manager.subscribe
```

While the default configurations are probably fine for most situations, you can configure both the internal HTTP server and the subscription manager when you call `on_event` by passing a configuration block:

```ruby
manager = service.on_event(callback) do |c|
  c.configure_http_listener do |l|
    l.listen_port = 8888
    l.bind_address = '192.168.1.100'
  end
  
  c.configure_subscription_manager do |m|
    m.requested_timeout = 1800
    m.resubscription_interval_buffer = 60
    m.existing_sid = 'uuid:6ef254f0-04d1-11e6-8000-fcf1524b4f9c'
    m.log_level = Logger::INFO
  end
end
```
