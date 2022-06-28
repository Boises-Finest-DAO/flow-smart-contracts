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
        access(account) var votingBalletCollections: @{UFix64: VotingCollection}
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

        pub fun getVotingBallets(): @{UInt64: SimpleDaoNFT.VotingCollection} {
            panic("TODO")
        }

        pub fun castVote(votingCollectionId: UInt64, token: @NonFungibleToken.NFT) {
            panic("TODO")
        }

        pub fun createProposal(name: String, description: String, type: String) {
            panic("TODO")
        }

        /****************** Getting a FLOAT ******************/

        // Will not panic if one of the recipients has already claimed.
        // It will just skip them.
        // pub fun batchMint(recipients: [&Collection{NonFungibleToken.CollectionPublic}]) {
        //     for recipient in recipients {
        //         if self.claimed[recipient.owner!.address] == nil {
        //             self.mint(recipient: recipient)
        //         }
        //     }
        // }


        // Used to give a person a FLOAT from this event.
        // Used as a helper function for `claim`, but can also be 
        // used by the event owner and shared accounts to
        // mint directly to a user. 
        //
        // If the event owner directly mints to a user, it does not
        // run the verifiers on the user. It bypasses all of them.
        //
        // Return the id of the FLOAT it minted
        pub fun mint(recipient: &Collection{NonFungibleToken.CollectionPublic}, params: {String: AnyStruct}): UInt64 {
            pre {
                self.claimed[recipient.owner!.address] == nil:
                    "This person already claimed their FLOAT!"
            }
            let recipientAddr: Address = recipient.owner!.address
            let serial = self.totalSupply

            let token <- create NFT(
                _name: params["name"] as! String,
                _dateJoined: params["dateJoined"] as! String,
                _originalRecipient: recipientAddr,
                _serial: serial,
                _simpleDaoAddr: self.addr,
                _simpleDaoName: self.name,
                _simpleDaoImage: self.image,
                _simpleDaoDescription: self.description,
                _simpleDaoId: self.simpleDaoId
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
            // params["event"] = &self as &FLOATEvent{FLOATEventPublic}
            // params["claimee"] = recipient.owner!.address
            
            // // Runs a loop over all the verifiers that this FLOAT Events
            // // implements. For example, "Limited", "Timelock", "Secret", etc.  
            // // All the verifiers are in the FLOATVerifiers.cdc contract
            // for identifier in self.verifiers.keys {
            //     let typedModules = (&self.verifiers[identifier] as &[{IVerifier}]?)!
            //     var i = 0
            //     while i < typedModules.length {
            //         let verifier = &typedModules[i] as &{IVerifier}
            //         verifier.verify(params)
            //         i = i + 1
            //     }
            // }

            // You're good to go.
            let id = self.mint(recipient: recipient, params: params)

            // emit FLOATClaimed(
            //     id: id,
            //     eventHost: self.host, 
            //     eventId: self.eventId, 
            //     eventImage: self.image,
            //     eventName: self.name,
            //     recipient: recipient.owner!.address,
            //     serial: self.totalSupply - 1
            // )
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
                self.claimed[recipient.owner!.address] == nil:
                    "This person already claimed their FLOAT!"
                self.claimable: 
                    "This FLOATEvent is not claimable, and thus not currently active."
            }
            
            self.verifyAndMint(recipient: recipient, params: params)
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
        ) {
            self.claimable = _claimable
            self.claimed = {}
            self.currentHolders = {}
            self.dateCreated = getCurrentBlock().timestamp
            self.description = _description
            self.simpleDaoId = self.uuid
            self.extraMetadata = _extraMetadata
            self.addr = _host
            self.image = _image
            self.name = _name
            self.transferrable = _transferrable
            self.totalSupply = 0
            self.url = _url
            self.votingBalletCollections <- {}

            SimpleDaoNFT.totalSimpleDAOs = SimpleDaoNFT.totalSimpleDAOs + 1
            // emit FLOATEventCreated(eventId: self.eventId, description: self.description, host: self.host, image: self.image, name: self.name, url: self.url)
        }

        destroy() {
            destroy self.votingBalletCollections
            // emit FLOATEventDestroyed(eventId: self.eventId, host: self.host, name: self.name)
        }
}
 
    // 
    // SimpleDaos
    //
    pub resource interface SimpleDAOsPublic {
        // Public Getters
        pub fun borrowPublicSimpleDaoRef(simpleDaoId: UInt64): &SimpleDAO{SimpleDAOPublic}?
        pub fun getAllSimpleDAOs(): {UInt64: String}
        pub fun getIDs(): [UInt64]
    }

    // A "Collection" of FLOAT Events
    pub resource SimpleDAOs: SimpleDAOsPublic, MetadataViews.ResolverCollection {
        // All the FLOAT Events this collection stores
        access(account) var simpleDAOs: @{UInt64: SimpleDAO}

        // Creates a new FLOAT Event by passing in some basic parameters
        // and a list of all the verifiers this event must abide by
        pub fun createEvent(
            claimable: Bool,
            description: String,
            image: String, 
            name: String, 
            transferrable: Bool,
            url: String,
            extraMetadata: {String: AnyStruct},
        ): UInt64 {
            let SimpleDAO <- create SimpleDAO(
                _claimable: claimable,
                _description: description, 
                _extraMetadata: extraMetadata,
                _host: self.owner!.address, 
                _image: image, 
                _name: name, 
                _transferrable: transferrable,
                _url: url,
            )
            let simpleDaoId = SimpleDAO.simpleDaoId
            self.simpleDAOs[simpleDaoId] <-! SimpleDAO

            return simpleDaoId
        }

        pub fun borrowSimpleDAOsRef(simpleDaoId: UInt64): &SimpleDAO? {
            return &self.simpleDAOs[simpleDaoId] as &SimpleDAO?
        }

        /************* Getters (for anyone) *************/

        // Get a public reference to the FLOATEvent
        // so you can call some helpful getters
        pub fun borrowPublicSimpleDaoRef(simpleDaoId: UInt64): &SimpleDAO{SimpleDAOPublic}? {
            return &self.simpleDAOs[simpleDaoId] as &SimpleDAO{SimpleDAOPublic}?
        }

        pub fun getIDs(): [UInt64] {
            return self.simpleDAOs.keys
        }

        // Maps the eventId to the name of that
        // event. Just a kind helper.
        pub fun getAllSimpleDAOs(): {UInt64: String} {
            let answer: {UInt64: String} = {}
            for id in self.simpleDAOs.keys {
                let ref = (&self.simpleDAOs[id] as &SimpleDAO?)!
                answer[id] = ref.name
            }
            return answer
        }

        pub fun borrowViewResolver(id: UInt64): &{MetadataViews.Resolver} {
            return (&self.simpleDAOs[id] as &{MetadataViews.Resolver}?)!
        }

        init() {
            self.simpleDAOs <- {}
        }

        destroy() {
            destroy self.simpleDAOs
        }
    }

    pub fun createEmptyCollection(): @Collection {
        return <- create Collection()
    }

    pub fun createEmptySimpleDAOsCollection(): @SimpleDAOs {
        return <- create SimpleDAOs()
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