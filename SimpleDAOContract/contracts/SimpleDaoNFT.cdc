import NonFungibleToken from "./core/NonFungibleToken.cdc"
import MetadataViews from "./core/MetadataViews.cdc"

pub contract SimpleDaoNFT: NonFungibleToken {
    /***********************************************/
    /******************** PATHS ********************/
    /***********************************************/
    pub let SimpleDAOStoragePath: StoragePath
    pub let SimpleDAOPublicPath: PublicPath
    pub let SimpleDAOPrivatePath: PrivatePath

    pub let SimpleDAOMemberStoragePath: StoragePath
    pub let SimpleDAOMemberPublicPath: PublicPath
    pub let SimpleDAOMemberPrivatePath: PrivatePath

    /************************************************/
    /******************** EVENTS ********************/
    /************************************************/
    pub event ContractInitialized()
    pub event SimpleDAOMemberMinted(id: UInt64, simpleDaoAddr: Address, simpleDaoId: UInt64, simpleDaoImage: String, recipient: Address, serial: UInt64)

    pub event Withdraw(id: UInt64, from: Address?)
    pub event Deposit(id: UInt64, to: Address?)

    /***********************************************/
    /******************** STATE ********************/
    /***********************************************/
    //Total SimpleDAOMembers that have ever been created (does not go down when a SimpleDAOMember is destroyed)
    pub var totalSupply: UInt64

    //The total amount of SimpleDAO's that have ever been created (does not go down when SimpleDAO is destroyed)
    pub var totalSimpleDAOs: UInt64

    /***********************************************/
    /**************** FUNCTIONALITY ****************/
    /***********************************************/

    // A helpful wrapper to contain an address, 
    // the id of a SimpleDAOMemb, and its serial
    pub struct TokenIdentifier {
        pub let id: UInt64
        pub let address: Address
        pub let serial: UInt64

        init(_id: UInt64, _address: Address, _serial: UInt64) {
            self.id = _id
            self.address = _address
            self.serial = _serial
        }
    }

    pub resource NFT: NonFungibleToken.INFT {
        // The `uuid` of this resource
        pub let id: UInt64

        //SimpleDAOMember Info
        pub let name: String
        pub let dateReceived: UFix64
        pub let dateJoined: String
        pub let votingBallets: @{UInt64: NonFungibleToken.NFT}
        pub let originalRecipient: Address
        pub let serial: UInt64

        //SimpleDAO Info - This info is duplicated incase the SimpleDAO is ever deleted or its public capabilites removed
        pub let simpleDaoAddr: Address
        pub let simpleDaoName: String
        pub let simpleDaoDescription: String
        pub let simpleDaoId: UInt64
        pub let simpleDaoImage: String

        // TO DO ******* - pub let simpleDaoCap:

        // pub fun getEventMetadata(): &FLOATEvent{FLOATEventPublic}? {
        //     if let events = self.eventsCap.borrow() {
        //         return events.borrowPublicEventRef(eventId: self.eventId)
        //     }
        //     return nil
        // }

        // This is for the MetdataStandard
        pub fun getViews(): [Type] {
             return [
                Type<MetadataViews.Display>(),
                Type<TokenIdentifier>()
            ]
        }

        // This is for the MetdataStandard
        pub fun resolveView(_ view: Type): AnyStruct? {
            switch view {
                case Type<MetadataViews.Display>():
                    return MetadataViews.Display(
                        name: self.simpleDaoName, 
                        description: self.simpleDaoDescription, 
                        file: MetadataViews.IPFSFile(cid: self.simpleDaoImage, path: nil)
                    )
                case Type<TokenIdentifier>():
                    return TokenIdentifier(
                        _id: self.id, 
                        _address: self.owner!.address,
                        _serial: self.serial
                    ) 
            }

            return nil
        }

        init(_name: String, _dateJoined: String, _originalRecipient: Address, _serial: UInt64, _simpleDaoAddr: Address, _simpleDaoName: String, _simpleDaoImage: String, _simpleDaoDescription: String, _simpleDaoId: UInt64) {
            self.id = self.uuid
            self.name = _name
            self.dateReceived = getCurrentBlock().timestamp
            self.dateJoined = _dateJoined
            self.votingBallets <- {}
            self.originalRecipient = _originalRecipient
            self.serial = _serial
            self.simpleDaoAddr = _simpleDaoAddr
            self.simpleDaoName = _simpleDaoName
            self.simpleDaoDescription = _simpleDaoDescription
            self.simpleDaoId = _simpleDaoId
            self.simpleDaoImage = _simpleDaoImage

            // Stores a capability to the FLOATEvents of its creator
            // self.eventsCap = getAccount(_eventHost).getCapability<&FLOATEvents{FLOATEventsPublic, MetadataViews.ResolverCollection}>(FLOAT.FLOATEventsPublicPath)

            emit SimpleDAOMemberMinted(
                id: self.id,
                simpleDaoAddr: self.simpleDaoAddr,
                simpleDaoId: self.simpleDaoId,
                simpleDaoImage: self.simpleDaoImage,
                recipient: self.originalRecipient,
                serial: self.serial
            )

            SimpleDaoNFT.totalSupply = SimpleDaoNFT.totalSupply + 1
        }

        destroy() {
            // MORE TO DO - SEE FLOAT FOR REF
            destroy self.votingBallets
        }
    }

    // A public interface for people to call into our Collection
    pub resource interface CollectionPublic {
        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT
        pub fun borrowSimpleDaoMember(id: UInt64): &NFT?
        pub fun borrowViewResolver(id: UInt64): &{MetadataViews.Resolver}
        pub fun deposit(token: @NonFungibleToken.NFT)
        pub fun getIDs(): [UInt64]
        pub fun getAllIDs(): [UInt64]
        pub fun ownedIdFromSimpleDao(simpleDaoId: UInt64): [UInt64]
    }

    pub resource Collection: NonFungibleToken.Provider, NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, MetadataViews.ResolverCollection, CollectionPublic {
        // Maps a SmartDAOMember id to the SmartDAOMember itself
        pub var ownedNFTs: @{UInt64: NonFungibleToken.NFT}

        // Maps a SmartDAO id to the SmartDAOMember that this user owns
        access(account) var simpleDaos: {UInt64: {UInt64: Bool}}

        // Deposits a SmartDAOMember to the collection
        pub fun deposit(token: @NonFungibleToken.NFT) {
            let nft <- token as! @NFT
            let id = nft.id
            let simpleDaoId = nft.simpleDaoId

            // Update self.simpleDaos to have this members id in it
            if self.simpleDaos[simpleDaoId] == nil {
                self.simpleDaos[simpleDaoId] = {id: true}
            } else {
                self.simpleDaos[simpleDaoId]!.insert(key: id, true)
            }

            // Try to update the FLOATEvent's current holders. This will
            // not work if they unlinked their FLOATEvent to the public,
            // and the data will go out of sync. But that is their fault.
            // if let floatEvent: &FLOATEvent{FLOATEventPublic} = nft.getEventMetadata() {
            //     floatEvent.updateFLOATHome(id: id, serial: nft.serial, owner: self.owner!.address)
            // }

            // emit Deposit(id: id, to: self.owner!.address)

            self.ownedNFTs[id] <-! nft
        }

        pub fun withdraw(withdrawID: UInt64): @NonFungibleToken.NFT {
            let token <- self.ownedNFTs.remove(key: withdrawID) ?? panic("This SmartDAOMember Token does not exist")
            let nft <- token as! @NFT
            let id = nft.id

            // Update self.simpleDaos[simpleDaoId] to not have this member id in it
            self.simpleDaos[nft.simpleDaoId]!.remove(key: id)

            // Try to update the FLOATEvent's current holders. This will
            // not work if they unlinked their FLOATEvent to the public,
            // and the data will go out of sync. But that is their fault.
            //
            // Additionally, this checks if the FLOATEvent host wanted this
            // FLOAT to be transferrable. Secondary marketplaces will use this
            // withdraw function, so if the FLOAT is not transferrable,
            // you can't sell it there.
            // if let floatEvent: &FLOATEvent{FLOATEventPublic} = nft.getEventMetadata() {
            //     assert(
            //         floatEvent.transferrable, 
            //         message: "This FLOAT is not transferrable."
            //     )
            //     floatEvent.updateFLOATHome(id: nft.id, serial: nft.serial, owner: nil)
            // }

            // emit Withdraw(id: id, from: self.owner!.address)
            return <- nft
        }

        // Only returns the FLOATs for which we can still
        // access data about their event.
        pub fun getIDs(): [UInt64] {
            let ids: [UInt64] = []
            for key in self.ownedNFTs.keys {
                let nftRef = self.borrowSimpleDaoMember(id: key)!
                // if nftRef.simpleDaoCap.check() {
                //     ids.append(key)
                // }
            }
            return ids
        }

        // Returns all the SimpleDAOMember ids
        pub fun getAllIDs(): [UInt64] {
            return self.ownedNFTs.keys
        }

        // Returns a SimpleDAOMember id that belongs tot he passed in simpleDaoId
        pub fun ownedIdFromSimpleDao(simpleDaoId: UInt64): [UInt64] {
            let answer: [UInt64] = []
            if let idsInSimpleDao = self.simpleDaos[simpleDaoId]?.keys {
                for id in idsInSimpleDao {
                    if self.ownedNFTs[id] != nil {
                        answer.append(id)
                    }
                }
            }
            return answer
        }

        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT {
            return (&self.ownedNFTs[id] as &NonFungibleToken.NFT?)!
        }

        pub fun borrowSimpleDaoMember(id: UInt64): &NFT? {
            if self.ownedNFTs[id] != nil {
                let ref = (&self.ownedNFTs[id] as auth &NonFungibleToken.NFT?)!
                return ref as! &NFT
            }
            return nil
        }

        pub fun borrowViewResolver(id: UInt64): &{MetadataViews.Resolver} {
            let tokenRef = (&self.ownedNFTs[id] as auth &NonFungibleToken.NFT?)!
            let nftRef = tokenRef as! &NFT
            return nftRef as &{MetadataViews.Resolver}
        }

        init() {
            self.ownedNFTs <- {}
            self.simpleDaos = {}
        }

        destroy() {
            destroy self.ownedNFTs
        }
    }

    pub resource VotingBallets {

    }

    pub resource VotingCollection {

    }

    // A public interface to read the SimpleDAO
    pub resource interface SimpleDAOPublic {
        pub var claimable: Bool
        pub let dateCreated: UFix64
        pub let description: String
        pub let simpleDaoId: UInt64
        pub let addr: Address
        pub let image: String
        pub let name: String
        pub var totalSupply: UInt64
        pub var transferrable: Bool
        pub let url: String
        pub fun claim(recipient: &Collection, params: {String: AnyStruct})
        pub fun getClaimed(): {Address: TokenIdentifier}
        pub fun getCurrentHolders(): {UInt64: TokenIdentifier}
        pub fun getCurrentHolder(serial: UInt64): TokenIdentifier?
        pub fun getExtraMetadata(): {String: AnyStruct}
        pub fun hasClaimed(account: Address): TokenIdentifier?
        pub fun getVotingBallets(): @{UInt64: VotingCollection}
        pub fun castVote(votingCollectionId: UInt64, token: @NonFungibleToken.NFT)
        pub fun createProposal(name: String, description: String, type: String)

        access(account) fun updateSimpleDaoMembeHome(id: UInt64, serial: UInt64, owner: Address?)
    }

    //SimpleDAO
    pub resource SimpleDAO: SimpleDAOPublic, MetadataViews.Resolver {
        // Whether or not anyone can join the DAO on their own
        pub var claimable: Bool
        // Maps an address to the SimpleDAOMember they claimed
        access(account) var claimed: {Address: TokenIdentifier}
        // Maps a serial to the person who theoretically owns
        // that SimpleDAOMember.
        access(account) var currentHolders: {UInt64: TokenIdentifier}
        pub let dateCreated: UFix64
        pub let description: String 
        // This is equal to this resource's uuid
        pub let simpleDaoId: UInt64
        access(account) var extraMetadata: {String: AnyStruct}
        // The groups that this FLOAT Event belongs to (groups
        // are within the FLOATEvents resource)
        access(account) var votingBalletCollections: {UFix64: Bool}
        // Who created this FLOAT Event
        pub let addr: Address
        // The image of the FLOAT Event
        pub let image: String 
        // The name of the FLOAT Event
        pub let name: String
        // The total number of FLOATs that have been
        // minted from this event
        pub var totalSupply: UInt64
        // Whether or not the FLOATs that users own
        // from this event can be transferred on the
        // FLOAT platform itself (transferring allowed
        // elsewhere)
        pub var transferrable: Bool
        // A url of where the event took place
        pub let url: String

        /***************** Setters for the Event Owner *****************/

        // Toggles claiming on/off
        pub fun toggleClaimable(): Bool {
            self.claimable = !self.claimable
            return self.claimable
        }

        // Toggles transferring on/off
        pub fun toggleTransferrable(): Bool {
            self.transferrable = !self.transferrable
            return self.transferrable
        }

        // Updates the metadata in case you want
        // to add something. 
        pub fun updateMetadata(newExtraMetadata: {String: AnyStruct}) {
            for key in newExtraMetadata.keys {
                if !self.extraMetadata.containsKey(key) {
                    self.extraMetadata[key] = newExtraMetadata[key]
                }
            }
        }

        /***************** Setters for the Contract Only *****************/

        // Called if a user moves their FLOAT to another location.
        // Needed so we can keep track of who currently has it.
        access(account) fun updateSimpleDaoMembeHome(id: UInt64, serial: UInt64, owner: Address?) {
            if owner == nil {
                self.currentHolders.remove(key: serial)
            } else {
                self.currentHolders[serial] = TokenIdentifier(
                    _id: id,
                    _address: owner!,
                    _serial: serial
                )
            }
            // emit FLOATTransferred(id: id, eventHost: self.host, eventId: self.eventId, newOwner: owner, serial: serial)
        }

        /***************** Getters (all exposed to the public) *****************/

        // Returns info about the FLOAT that this account claimed
        // (if any)
        pub fun hasClaimed(account: Address): TokenIdentifier? {
            return self.claimed[account]
        }

        // This is a guarantee that the person owns the FLOAT
        // with the passed in serial
        pub fun getCurrentHolder(serial: UInt64): TokenIdentifier? {
            pre {
                self.currentHolders[serial] != nil:
                    "This serial has not been created yet."
            }
            let data = self.currentHolders[serial]!
            let collection = getAccount(data.address).getCapability(SimpleDaoNFT.SimpleDAOMemberPublicPath).borrow<&Collection{CollectionPublic}>() 
            if collection?.borrowSimpleDaoMember(id: data.id) != nil {
                return data
            }
                
            return nil
        }

        // Returns an accurate dictionary of all the
        // claimers
        pub fun getClaimed(): {Address: TokenIdentifier} {
            return self.claimed
        }

        // This dictionary may be slightly off if for some
        // reason the FLOATEvents owner ever unlinked their
        // resource from the public.  
        // Use `getCurrentHolder(serial: UInt64)` to truly
        // verify if someone holds that serial.
        pub fun getCurrentHolders(): {UInt64: TokenIdentifier} {
            return self.currentHolders
        }

        pub fun getExtraMetadata(): {String: AnyStruct} {
            return self.extraMetadata
        }

        pub fun getViews(): [Type] {
             return [
                Type<MetadataViews.Display>()
            ]
        }

        pub fun resolveView(_ view: Type): AnyStruct? {
            switch view {
                case Type<MetadataViews.Display>():
                    return MetadataViews.Display(
                        name: self.name, 
                        description: self.description, 
                        file: MetadataViews.IPFSFile(cid: self.image, path: nil)
                    )
            }

            return nil
        }

        /****************** Getting a FLOAT ******************/

        // Will not panic if one of the recipients has already claimed.
        // It will just skip them.
        pub fun batchMint(recipients: [&Collection{NonFungibleToken.CollectionPublic}]) {
            for recipient in recipients {
                if self.claimed[recipient.owner!.address] == nil {
                    self.mint(recipient: recipient)
                }
            }
        }


        // Used to give a person a FLOAT from this event.
        // Used as a helper function for `claim`, but can also be 
        // used by the event owner and shared accounts to
        // mint directly to a user. 
        //
        // If the event owner directly mints to a user, it does not
        // run the verifiers on the user. It bypasses all of them.
        //
        // Return the id of the FLOAT it minted
        pub fun mint(recipient: &Collection{NonFungibleToken.CollectionPublic}): UInt64 {
            pre {
                self.claimed[recipient.owner!.address] == nil:
                    "This person already claimed their FLOAT!"
            }
            let recipientAddr: Address = recipient.owner!.address
            let serial = self.totalSupply

            let token <- create NFT(
                _eventDescription: self.description,
                _eventHost: self.host, 
                _eventId: self.eventId,
                _eventImage: self.image,
                _eventName: self.name,
                _originalRecipient: recipientAddr, 
                _serial: serial
            ) 
            let id = token.id
            // Saves the claimer
            self.claimed[recipientAddr] = TokenIdentifier(
                _id: id,
                _address: recipientAddr,
                _serial: serial
            )
            // Saves the claimer as the current holder
            // of the newly minted FLOAT
            self.currentHolders[serial] = TokenIdentifier(
                _id: id,
                _address: recipientAddr,
                _serial: serial
            )

            self.totalSupply = self.totalSupply + 1
            recipient.deposit(token: <- token)
            return id
        }

        access(account) fun verifyAndMint(recipient: &Collection, params: {String: AnyStruct}): UInt64 {
            params["event"] = &self as &FLOATEvent{FLOATEventPublic}
            params["claimee"] = recipient.owner!.address
            
            // Runs a loop over all the verifiers that this FLOAT Events
            // implements. For example, "Limited", "Timelock", "Secret", etc.  
            // All the verifiers are in the FLOATVerifiers.cdc contract
            for identifier in self.verifiers.keys {
                let typedModules = (&self.verifiers[identifier] as &[{IVerifier}]?)!
                var i = 0
                while i < typedModules.length {
                    let verifier = &typedModules[i] as &{IVerifier}
                    verifier.verify(params)
                    i = i + 1
                }
            }

            // You're good to go.
            let id = self.mint(recipient: recipient)

            emit FLOATClaimed(
                id: id,
                eventHost: self.host, 
                eventId: self.eventId, 
                eventImage: self.image,
                eventName: self.name,
                recipient: recipient.owner!.address,
                serial: self.totalSupply - 1
            )
            return id
        }

        // For the public to claim FLOATs. Must be claimable to do so.
        // You can pass in `params` that will be forwarded to the
        // customized `verify` function of the verifier.  
        //
        // For example, the FLOAT platform allows event hosts
        // to specify a secret phrase. That secret phrase will 
        // be passed in the `params`.
        pub fun claim(recipient: &Collection, params: {String: AnyStruct}) {
            pre {
                self.getPrices() == nil:
                    "You need to purchase this FLOAT."
                self.claimed[recipient.owner!.address] == nil:
                    "This person already claimed their FLOAT!"
                self.claimable: 
                    "This FLOATEvent is not claimable, and thus not currently active."
            }
            
            self.verifyAndMint(recipient: recipient, params: params)
        }
 
        pub fun purchase(recipient: &Collection, params: {String: AnyStruct}, payment: @FungibleToken.Vault) {
            pre {
                self.getPrices() != nil:
                    "Don't call this function. The FLOAT is free."
                self.getPrices()![payment.getType().identifier] != nil:
                    "This FLOAT does not support purchasing in the passed in token."
                payment.balance == self.getPrices()![payment.getType().identifier]!.price:
                    "You did not pass in the correct amount of tokens."
                self.claimed[recipient.owner!.address] == nil:
                    "This person already claimed their FLOAT!"
                self.claimable: 
                    "This FLOATEvent is not claimable, and thus not currently active."
            }
            let royalty: UFix64 = 0.05
            let emeraldCityTreasury: Address = 0x5643fd47a29770e7
            let paymentType: String = payment.getType().identifier
            let tokenInfo: TokenInfo = self.getPrices()![paymentType]!

            let EventHostVault = getAccount(self.host).getCapability(tokenInfo.path)
                                    .borrow<&{FungibleToken.Receiver}>()
                                    ?? panic("Could not borrow the &{FungibleToken.Receiver} from the event host.")

            assert(
                EventHostVault.getType().identifier == paymentType,
                message: "The event host's path is not associated with the intended token."
            )
            
            let EmeraldCityVault = getAccount(emeraldCityTreasury).getCapability(tokenInfo.path)
                                    .borrow<&{FungibleToken.Receiver}>() 
                                    ?? panic("Could not borrow the &{FungibleToken.Receiver} from Emerald City's Vault.")

            assert(
                EmeraldCityVault.getType().identifier == paymentType,
                message: "Emerald City's path is not associated with the intended token."
            )

            let emeraldCityCut <- payment.withdraw(amount: payment.balance * royalty)

            EmeraldCityVault.deposit(from: <- emeraldCityCut)
            EventHostVault.deposit(from: <- payment)

            let id = self.verifyAndMint(recipient: recipient, params: params)

            emit FLOATPurchased(id: id, eventHost: self.host, eventId: self.eventId, recipient: recipient.owner!.address, serial: self.totalSupply - 1)
        }

        init (
            _claimable: Bool,
            _description: String, 
            _extraMetadata: {String: AnyStruct},
            _host: Address, 
            _image: String, 
            _name: String,
            _transferrable: Bool,
            _url: String,
            _verifiers: {String: [{IVerifier}]},
        ) {
            self.claimable = _claimable
            self.claimed = {}
            self.currentHolders = {}
            self.dateCreated = getCurrentBlock().timestamp
            self.description = _description
            self.eventId = self.uuid
            self.extraMetadata = _extraMetadata
            self.groups = {}
            self.host = _host
            self.image = _image
            self.name = _name
            self.transferrable = _transferrable
            self.totalSupply = 0
            self.url = _url
            self.verifiers = _verifiers

            FLOAT.totalFLOATEvents = FLOAT.totalFLOATEvents + 1
            emit FLOATEventCreated(eventId: self.eventId, description: self.description, host: self.host, image: self.image, name: self.name, url: self.url)
        }

        destroy() {
            emit FLOATEventDestroyed(eventId: self.eventId, host: self.host, name: self.name)
        }
    }

    // A container of FLOAT Events (maybe because they're similar to
    // one another, or an event host wants to list all their AMAs together, etc).
    pub resource Group {
        pub let id: UInt64
        pub let name: String
        pub let image: String
        pub let description: String
        // All the FLOAT Events that belong
        // to this group.
        access(account) var events: {UInt64: Bool}

        access(account) fun addEvent(eventId: UInt64) {
            self.events[eventId] = true
        }

        access(account) fun removeEvent(eventId: UInt64) {
            self.events.remove(key: eventId)
        }

        pub fun getEvents(): [UInt64] {
            return self.events.keys
        }

        init(_name: String, _image: String, _description: String) {
            self.id = self.uuid
            self.name = _name
            self.image = _image
            self.description = _description
            self.events = {}
        }
    }
 
    // 
    // FLOATEvents
    //
    pub resource interface FLOATEventsPublic {
        // Public Getters
        pub fun borrowPublicEventRef(eventId: UInt64): &FLOATEvent{FLOATEventPublic}?
        pub fun getAllEvents(): {UInt64: String}
        pub fun getIDs(): [UInt64]
        pub fun getGroup(groupName: String): &Group?
        pub fun getGroups(): [String]
        // Account Getters
        access(account) fun borrowEventsRef(): &FLOATEvents
    }

    // A "Collection" of FLOAT Events
    pub resource FLOATEvents: FLOATEventsPublic, MetadataViews.ResolverCollection {
        // All the FLOAT Events this collection stores
        access(account) var events: @{UInt64: FLOATEvent}
        // All the Groups this collection stores
        access(account) var groups: @{String: Group}

        // Creates a new FLOAT Event by passing in some basic parameters
        // and a list of all the verifiers this event must abide by
        pub fun createEvent(
            claimable: Bool,
            description: String,
            image: String, 
            name: String, 
            transferrable: Bool,
            url: String,
            verifiers: [{IVerifier}],
            _ extraMetadata: {String: AnyStruct},
            initialGroups: [String]
        ): UInt64 {
            let typedVerifiers: {String: [{IVerifier}]} = {}
            for verifier in verifiers {
                let identifier = verifier.getType().identifier
                if typedVerifiers[identifier] == nil {
                    typedVerifiers[identifier] = [verifier]
                } else {
                    typedVerifiers[identifier]!.append(verifier)
                }
            }

            let FLOATEvent <- create FLOATEvent(
                _claimable: claimable,
                _description: description, 
                _extraMetadata: extraMetadata,
                _host: self.owner!.address, 
                _image: image, 
                _name: name, 
                _transferrable: transferrable,
                _url: url,
                _verifiers: typedVerifiers
            )
            let eventId = FLOATEvent.eventId
            self.events[eventId] <-! FLOATEvent

            for groupName in initialGroups {
                self.addEventToGroup(groupName: groupName, eventId: eventId)
            }
            return eventId
        }

        // Deletes an event. Also makes sure to remove
        // the event from all the groups its in.
        pub fun deleteEvent(eventId: UInt64) {
            let event <- self.events.remove(key: eventId) ?? panic("This event does not exist")
            for groupName in event.getGroups() {
                let groupRef = (&self.groups[groupName] as &Group?)!
                groupRef.removeEvent(eventId: eventId)
            }
            destroy event
        }

        pub fun createGroup(groupName: String, image: String, description: String) {
            pre {
                self.groups[groupName] == nil: "A group with this name already exists."
            }
            self.groups[groupName] <-! create Group(_name: groupName, _image: image, _description: description)
        }

        // Deletes a group. Also makes sure to remove
        // the group from all the events that use it.
        pub fun deleteGroup(groupName: String) {
            let eventsInGroup = self.groups[groupName]?.getEvents() 
                                ?? panic("This Group does not exist.")
            for eventId in eventsInGroup {
                let ref = (&self.events[eventId] as &FLOATEvent?)!
                ref.removeFromGroup(groupName: groupName)
            }
            destroy self.groups.remove(key: groupName)
        }

        // Adds an event to a group. Also adds the group
        // to the event.
        pub fun addEventToGroup(groupName: String, eventId: UInt64) {
            pre {
                self.groups[groupName] != nil: "This group does not exist."
                self.events[eventId] != nil: "This event does not exist."
            }
            let groupRef = (&self.groups[groupName] as &Group?)!
            groupRef.addEvent(eventId: eventId)

            let eventRef = self.borrowEventRef(eventId: eventId)!
            eventRef.addToGroup(groupName: groupName)
        }

        // Simply takes the event away from the group
        pub fun removeEventFromGroup(groupName: String, eventId: UInt64) {
            pre {
                self.groups[groupName] != nil: "This group does not exist."
                self.events[eventId] != nil: "This event does not exist."
            }
            let groupRef = (&self.groups[groupName] as &Group?)!
            groupRef.removeEvent(eventId: eventId)

            let eventRef = self.borrowEventRef(eventId: eventId)!
            eventRef.removeFromGroup(groupName: groupName)
        }

        pub fun getGroup(groupName: String): &Group? {
            return &self.groups[groupName] as &Group?
        }
        
        pub fun getGroups(): [String] {
            return self.groups.keys
        }

        // Only accessible to people who share your account. 
        // If `fromHost` has allowed you to share your account
        // in the GrantedAccountAccess.cdc contract, you can get a reference
        // to their FLOATEvents here and do pretty much whatever you want.
        pub fun borrowSharedRef(fromHost: Address): &FLOATEvents {
            let sharedInfo = getAccount(fromHost).getCapability(GrantedAccountAccess.InfoPublicPath)
                                .borrow<&GrantedAccountAccess.Info{GrantedAccountAccess.InfoPublic}>() 
                                ?? panic("Cannot borrow the InfoPublic from the host")
            assert(
                sharedInfo.isAllowed(account: self.owner!.address),
                message: "This account owner does not share their account with you."
            )
            let otherFLOATEvents = getAccount(fromHost).getCapability(FLOAT.FLOATEventsPublicPath)
                                    .borrow<&FLOATEvents{FLOATEventsPublic}>()
                                    ?? panic("Could not borrow the public FLOATEvents.")
            return otherFLOATEvents.borrowEventsRef()
        }

        // Only used for the above function.
        access(account) fun borrowEventsRef(): &FLOATEvents {
            return &self as &FLOATEvents
        }

        pub fun borrowEventRef(eventId: UInt64): &FLOATEvent? {
            return &self.events[eventId] as &FLOATEvent?
        }

        /************* Getters (for anyone) *************/

        // Get a public reference to the FLOATEvent
        // so you can call some helpful getters
        pub fun borrowPublicEventRef(eventId: UInt64): &FLOATEvent{FLOATEventPublic}? {
            return &self.events[eventId] as &FLOATEvent{FLOATEventPublic}?
        }

        pub fun getIDs(): [UInt64] {
            return self.events.keys
        }

        // Maps the eventId to the name of that
        // event. Just a kind helper.
        pub fun getAllEvents(): {UInt64: String} {
            let answer: {UInt64: String} = {}
            for id in self.events.keys {
                let ref = (&self.events[id] as &FLOATEvent?)!
                answer[id] = ref.name
            }
            return answer
        }

        pub fun borrowViewResolver(id: UInt64): &{MetadataViews.Resolver} {
            return (&self.events[id] as &{MetadataViews.Resolver}?)!
        }

        init() {
            self.events <- {}
            self.groups <- {}
        }

        destroy() {
            destroy self.events
            destroy self.groups
        }
    }

    pub fun createEmptyCollection(): @Collection {
        return <- create Collection()
    }

    pub fun createEmptyFLOATEventCollection(): @FLOATEvents {
        return <- create FLOATEvents()
    }

    init() {
        self.SimpleDAOStoragePath = /storage/SimpleDAO
        self.SimpleDAOPublicPath = /public/SimpleDAO
        self.SimpleDAOPrivatePath = /private/SimpleDAO
        self.SimpleDAOMemberStoragePath = /storage/SimpleDAOMember
        self.SimpleDAOMemberPublicPath = /public/SimpleDAOMember
        self.SimpleDAOMemberPrivatePath = /private/SimpleDAOMember

        self.totalSupply = 0
        self.totalSimpleDAOs = 0
    }
}