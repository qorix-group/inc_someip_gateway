# E2E approach
As per SOME/IP gateway requirements, the E2E handling is split between gateway and the applications. The responsibilities are described below

## Gateway

### SOME/IP incomming data

- E2E value is extracted from SOME/IP payload
- CRC check is computed
- Sequnce conunter check is computed

After above, the gateway does SOME/IP to ABI Compatible Data Types deserialization and forwards deserialized `data`, `e2e_value` and computed `gateway_check` to interested participants.

### SOME/IP outgoing data

- E2E is computed only in `gateway`
- E2E is serilized with data into SOME/IP payload and send over


## Applications

## Incomming data

- Does a `check` before accessing data and handles both `gateway` computed E2E errors and `locally` computed errors (like to big hop in sequnce, etc.)

## Outgoing data

- Put produced data into IPC

# Implementation
To achieve E2E handling along with an API that make usere hard to forget checking for potential errors the following solution was implemented

## Wrapper type
Each `E2E` protected type that shall participate in IPC must be wrapped into `E2EProtected<T>` wrapper type. This type makes sure that before data is accessed, the checking of errors is done by the user.

## Type connection to E2E
Each `E2E` protected type has connected `trait` that describes which `E2E` profile shall be used for that type



#### Outgoing data

```plantuml

box App1

    participant Producer

end box

participant MwCom

box App2
    participant Consumer
    participant ConsumerCode
end box

participant Gateway
participant SOMEIP


->Producer: SomeData
Producer -> Producer: E2EProtectedType::<SomeData>.from_local(SomeData)

note right of Producer
The internal marks that a type was produced locally
end note

Producer -> MwCom: send(...)

...

group paraller
    group case1
        MwCom -> Consumer: new sample
        Consumer -> Consumer++: E2EProtectedType.check()

        alt SAMPLE_PRODUCED_LOCALLY
            Consumer -> ConsumerCode: Ok(SomeData) given to user
            note right
            Almost no runtime effort on checking in local path
            end note

        else NON_LOCAL_PRODUCER_DESCRIBED_IN_SECOND_DIAGRAM
        end alt
    end group

    group case2
        MwCom -> Gateway: new sample
        Gateway -> Gateway++
        Gateway -> Gateway: Compute E2E and serialize with SomeData
        Gateway -> SOMEIP: notify(...)
    end group

end group

```

#### Incomming data

```plantuml

participant SOMEIP
participant Gateway
participant MwCom





box App2
    participant Consumer
    participant ConsumerCode
end box





->SOMEIP: SOME/IP payload
SOMEIP -> Gateway: SOME/IP payload
Gateway -> Gateway: Extract E2E
Gateway -> Gateway: Compute E2E


Gateway -> MwCom: send
...

MwCom -> Consumer: new sample
alt GATEWAY_NO_ERROR
    Consumer -> Consumer: SomeData::E2EUserProfile.check()
    alt USER_PROFILE_CHECK_OK
        Consumer -> ConsumerCode: Ok(SomeData) given to user
    else
        Consumer -> ConsumerCode: Err(E2EErrorLocal::LocalError)
    end alt

else CRC_ERROR | SEQUENCE_ERROR
    Consumer -> ConsumerCode: (e2e_value, E2EUncheckedType<SomeData>)
    note right
        Gives the E2E value to user and an refernce to data that can be accessed unsafely if user need to.
    end note
end alt
```
 