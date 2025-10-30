# SOME/IP Design for S-CORE

WIP 

## References

- [S-CORE Feature request](https://eclipse-score.github.io/score/main/features/communication/some_ip_gateway/index.html)


## Repository structure
Design component are split as follows:
- `gateway_common` - all common types and traits used across whole implementation
- `gateway_generated` - generated code for SOME/IP gateway + specific `trait` definitions as the extended types are out of this   crates so `traits` needs to be here and not in `common`
- `gateway` - gateway `main` entrypoint that gathers are elements and run them
- `gateway_someip_adapters` - place where different SOME/IP Adapters can be implemented depending on project

## Key functional component
The gateway need to consist of few, isolated components/functionalities:
 - `SOME/IP` stack interface - used to talk to `SOME/IP`. This shall be higher, but type-less form of interface where
    rest of code can:
    - find services
    - offer services
    - receive SOME/IP messages as metadata and raw payload

 - `ACL` component - currently `?`, but it shall just filter out incoming traffic by rules and ie not allow to see services which are not white listed
 - `Payload transformer` - auto-generated code that can converter `mw_com types <-> SOME/IP payload`
 - `E2E` protection - WIP
 - `ServiceBridge` - bridging of services `local` to `SOME/IP` and vice versa

## Bridging Design
SOME/IP gateway will expose only **whole** services as visible outside. This means that what will be `offered` or `find`
on `SOME/IP SD` is the `Interface` description in meaning of `mw_com` component. This `Interface` together with `service_id` and `instance_id` will form service visible by any SOME/IP participant 

### Mapping of communication patterns

#### Local to SOME/IP 

##### `mw_com::Publisher`
Visible on **SOME/IP** as `Event` or `Field`

##### `mw_com::MethodServer` - `request - response`, currently skipped


#### SOME/IP to Local

##### Event or Field
Visible on `local` as `mw_com::Publisher` that can be subscribed to.

##### Request-Response  - currently skipped

### Static view

![Static View](./static_diagram.drawio.svg)

### Dynamic view

#### Bridging Local Service to SOME/IP procedure
```plantuml
start
:Create **LocalToSomeIpBridge<VehicleInterface>** instance with InstanceSpecifier;
:Execute **.bridge()** on instance;

repeat
    :Check for **VehicleInterface** service instance **locally**;
repeat while (Instance present) is (no) not (yes)

:Offer service on **SOME/IP** using **SomeIPServiceDescription**;

repeat
    :Subscribe to **local** Publisher;
    :Spawn **async task** with subscription that **receive** samples and send them to SOME/IP;
repeat while (Each **Publisher** in **VehicleInterface** was spawned) is (no) not (yes)

:Wait until error or **Service** unoffer;

```

#### Bridging Local Events to SOME/IP

```puml
box gateway #LightBlue
    participant Config
    participant "LocalToSomeIPBridge<VehicleConsumer>" as LocalToSomeIPBridge
end box


box mw_com_generated 
    participant VehicleConsumer
end box

box gateway_adapters #LightBlue
    participant SomeIPAdapter
end box



box mw_com
   participant IPCRuntime
   participant Subscriber
   participant Sample
end box

-> Config: create_local_to_someip_bridge()

Config -> LocalToSomeIPBridge: new(someip_service_desc, ipc_runtime, someip_adapter)
note right
Config will put each instance into separate task via **spawn**
end note

...
LocalToSomeIPBridge -> LocalToSomeIPBridge++: start().await
LocalToSomeIPBridge -> SomeIPAdapter: register_host_half(self)
note right of SomeIPAdapter
**register_host_half** registers current instance to receive traffic for SOME/IP.
If there is any traffic for this service (ie method request)
it will be delivered to this instance.
end note

LocalToSomeIPBridge -> IPCRuntime: find_service().await
...
LocalToSomeIPBridge -> SomeIPAdapter: offer_service(someip_service_desc)


LocalToSomeIPBridge -> VehicleConsumer: bridge()
group AsyncTask
    loop subscriber in VehicleConsumer
        VehicleConsumer -> Future**: bridge_event()
        Future -> Subscriber: subscribe()
        Subscriber --> Subscription**
        loop
            Future -> Subscription: try_receive()
            alt SAMPLE_AVAILABLE
                Future -> Sample: to_someip()
                Sample --> Future: SERIALIZED_PAYLOAD
                Future -> Future: calculate_e2e(SERIALIZED_PAYLOAD)
                Future -> SomeIPAdapter: notify_event(SERIALIZED_PAYLOAD)
            end
        end loop
    end loop

    VehicleConsumer -> VehicleConsumer: spawn(all_subscribers_futures)
    note right of VehicleConsumer
    This spawns a task where all futures are awaited till **error** or **shutdown**.
    All subscribers are placed in single task however this can be **generation**
    specific
    end note

end group

VehicleConsumer --> LocalToSomeIPBridge: JoinHandle
LocalToSomeIPBridge -> LocalToSomeIPBridge: join_all(JoinHandle, Shutdown).await
```

#### Bridging SOME/IP Events to Local IPC

```puml

box gateway #LightBlue
    participant Main
    participant Config
    participant "SomeIPToLocalBridge<VehicleProducer>" as SomeIPToLocalBridge
end box

box mw_com_generated 
    participant VehicleProducer
    participant OfferedVehicleProducer
end box

box gateway_adapters #LightBlue
    participant SomeIPAdapter
end box

box mw_com
   participant IPCRuntime
   participant Publisher
end box

Main -> Config: create_someip_to_local_bridge(someip_service_desc, ipc_runtime, someip_adapter)
Config -> SomeIPToLocalBridge**

Main -> Main++: spawn
Main -> SomeIPAdapter: start().await
note right
From now on, incoming SOME/IP traffic is routed to registered instances.
This is implementation specific, but current implementation for COVESA
is doing here find_service for each registered client
end note

...

-> SomeIPAdapter:    NEW_DATA_INCOMING

alt DETECTED_SERVICE_STATE_CHANGED

    SomeIPAdapter -> SomeIPToLocalBridge: service_state_changed(STATE)
    alt SERVICE_AVAILABLE
        SomeIPToLocalBridge -> VehicleProducer!!: offer()
        VehicleProducer --> OfferedVehicleProducer**
        VehicleProducer --> SomeIPToLocalBridge
    else SERVICE_UNAVAILABLE
        SomeIPToLocalBridge --> OfferedVehicleProducer!!: unoffer()
        note right
        Here VehicleProducer is again created - no more offering
        end note
    end

else RECEIVE_EVENT
    SomeIPAdapter -> SomeIPToLocalBridge: receive_event(event_id, payload)
    SomeIPToLocalBridge -> OfferedVehicleProducer: get_publisher(event_id)
    SomeIPToLocalBridge -> Publisher++: bridge_event(payload)

    note right
    **bridge_event** is blanket impl 
    for Publisher in gateway_generated crate
    end note

    Publisher -> Publisher: compute_e2e()
    Publisher -> Publisher: from_someip(payload)
    Publisher -> Publisher: allocate()
    Publisher -> Publisher: write(sample, e2e_raw, e2e_status)
    Publisher -> Publisher: send()
end alt

```























