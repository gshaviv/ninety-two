# Sqlable

Sqlable is a Swift library for storing data in a SQLite database easy as pie. Create a struct, make it Sqlable, and then read, write, update and delete to your heart’s content!

## Why would I want that?

Persistence is often a pain when making iOS apps. If you want to only use 1st party frameworks from Apple, your choice is either Core Data, or serializing to JSON or plist files. there’s a few nice 3rd party options, like Realm, but that’s mostly active objects doing a lot of dynamic things behind your back. If you want to just operate on plain structs, and just want to read and write to a database, Sqlable is the simplest option.

## Show me how to use it!

Suppose you have this struct:

```swift
struct Bicycle {
	let id : Int?
	var name : String
	var color : String
}
```

And you want to persist this in a database. To do this, you just make your struct Sqlable by implementing the Sqlable protocol like this:

```swift
extension Bicycle : Sqlable {
	static let id = Column("id", .integer, PrimaryKey(autoincrement: true))
	static let name = Column("name", .text)
	static let color = Column("color", .text)
	static let tableLayout = [id, name, color]
	
	func valueForColumn(column : Column) -> SqlValue? {
		switch column {
		case Bicycle.id: return id
		case Bicycle.name: return name
		case Bicycle.color: return color
		case _: return nil
		}
	}
	
	init(row : ReadRow) throws {
		id = try row.get(Bicycle.id)
		name = try row.get(Bicycle.name)
		color = try row.get(Bicycle.color)
	}
}
```

These are the only three things you need to specify:

• The table layout (which columns do you want stored)

• How to save a column

• How to read a row

And when you’ve done that, you can start using your struct with SQLite!

The first step to using it is to setup a new SQLite database and create the table for the bicycle:

```swift
db = try SqliteDatabase(filepath: documentsPath() + "/db.sqlite")
try db.createTable(Bicycle.self)
```

And then you’re ready to write, read, update and delete bicycles from the database!

```swift
// Insert bicycle
var bike = Bicycle(id: 1, name: "My bike", color: "Black")
try bike.insert().run(db)

// Read all bicycles
let bicycles = try Bicycle.read().run(db)

// Read some bicycles
let redBikes = try Bicycle.read().filter(Bicycle.color == "red").limit(3).run(db)

// Count all bicycles
let bicycleCount = try Bicycle.count().run(db)

// Update a bicycle
bike.name = "Sportsbike"
try bike.update().run(db)

// Delete bike
try bike.delete().run(db)
```

## New in version 1.2

### Update callbacks

You can now very easily observe changes via update callbacks on inserts, deletes and updates.

```swift
db.observe(.insert, on: Bicycle.self) { id in
	print("Inserted bicycle \(id)")
}

db.observe(.update, on: Bicycle.self, id: 2) { id in
	print("bicycle 2 has been updated")
}
```

### Concurrency

Sqlable now uses SQLites write-ahead log, which makes concurrent operations fast and easy. And since Sqlable is operating with plain structs, you can freely pass information between different threads.

```swift
let child = try db.createChild()

dispatch_async(background_queue) {
	let bicycles = try! Bicycle.read().run(child)
	
	dispatch_async(main_queue) {
		self.displayData(bicycles)
	}
}
```

You can use transactions to lock the database, and other threads will wait until the transaction is done.

### Full documentation

All public functions now have documentation 😎

## New in 1.1 (+1.1.1)

• Nested transactions

• SQL function calling for filters (e.g. "like", "upper" and "lower")

## What other cool features does it have?

### Transactions

Transactions are very simple to do:

```swift
try db.transaction { db in
	if try Bicycle.count().run(db) == 0 {
		try bike.insert().run(db)
	}
}
```

You can also do rollbacks:

```swift
try db.beginTransaction()
try bike.insert().run(db)
try db.rollbackTransaction()
```

And nested transactions! (*new in 1.1.1!*)

```swift
try db.transaction { db in
	try db.transaction { db in
		if try Bicycle.count().run(db) == 0 {
			try bike.insert().run(db)
		}
	}
}
```

### Foreign key constraints

```swift
extension Bicycle : Sqlable {
	static let ownerId = Column("owner_id", .Integer, ForeignKey<Person>())
	...
```

And you can also specify other columns and delete/update rules:

```swift
extension Bicycle : Sqlable {
	static let ownerId = Column("owner_id", .Integer, ForeignKey<Person>(column: Person.regId, onDelete: .cascade))
	...
```

### Uniqueness constraints

(*New in 1.1!*)

If you want each bicycle in the database to have a unique name:

```swift
extension Bicycle : Sqlable {
	static let name = Column("name", .text)
	static let tableConstraints : [TableConstraint] = [Unique(Bicycle.name)]
	...
```

Or, if you want the combination of name and color to be unique:

```swift
extension Bicycle : Sqlable {
	static let name = Column("name", .text)
	static let color = Column("color", .text)
	static let tableConstraints : [TableConstraint] = [Unique(Bicycle.name, Bicycle.color)]
	...
```

### DSL for query filters

```swift
Bicycle.read().filter(Bicycle.color == "red" && !(Bicycle.id == 0 || Bicycle.id > 1000))
```

### Update callback

(*New in 1.2!*)

Register the `didUpdate` callback on your database handler to get notified when anything changes:

```swift
db.didUpdate = { table, id, change in
	switch change {
	case .insert: print("Inserted \(id) into \(table)")
	case .update: print("Updated \(id) in \(table)")
	case .delete: print("Deleted \(id) from \(table)")
	}
}
```

But even better, you can register event callbacks on specific actions, tables and ids:

```swift
db.observe(.insert, on: Bicycle.self) { id in
	print("Inserted bicycle \(id)")
}

db.observe(.update, on: Bicycle.self, id: 2) { id in
	print("bicycle 2 has been updated")
}

db.observe(.delete, on: Bicycle.self) { id in
	print("bicycle \(id) has been deleted")
}

db.observe(on: Bicycle.self) { id in
	print("Something was updated on bicycle \(id)")
}
```

### Swift style error handling

Every function call that can fail is marked with throws, so you can handle every error that can possibly happen.

The APIs are also constructed so that you can set up your statements without touching the database, so you can set everything up without any error handling:

```swift
let idFilter = Bicycle.id > 2 && Bicyckle.id < 10
let read = Bicycle.read().filter(idFilter).limit(2)

do {
	let result = read.run(db)
} catch let error {
	// handle error
}
```

It also supports an optional handy callback for when any error occurs, which you can use if it fits into your app. Just call the `fail` method on your database handler when you encounter an error like this:

```swift
do {
	try Bicycle.read().limit(-1).run(db)
} catch let error {
	db.fail(error)
}
```

And it will be passed to your registered error handler:

```swift
db.didFail = { error in
	print("Oh no! \(error)")
}
```

### Concurrency

(*new in 1.2!*)

Ever had to deal with concurrency in Core Data? Don't worry, Sqlable is nothing like that.

Each SqliteDatabase instance is unique to one thread/queue. If you want to run some code in the background, you can create a child instance:

```swift
let child = try db.createChild()

dispatch_async(background_queue) {
	for bicycle in try! Bicycle.read().run(child) {
		...
	}
}
```

That's the only rule: keep each instance unique on its thread/queue. Sqlable and Sqlite will take care of locking the database correctly. The parent will even get update notifications from changes made in the child. If you want some database operations to happen serially, you can put them in a transaction, which will automatically lock the database on all threads.

Also, since model instances are just value types, you can freely move them around on threads. If you need to load 10.000.000 bicycles from your database, just run the read query in the background, and dispatch the result to the main queue.

## How do I install it?

If you’re using Carthage (you should!), just add this to your Cartfile:

```
github "ulrikdamm/Sqlable"
```

And then just in your source files:

```swift
import Sqlable
```

And you’re good to go!

## Which features are coming soon?

• Migrations

• Joins

## More technical details

### Statements

When you make a struct Sqlable, it gains instance- and static methods for returning statements. These methods are `read`, `count`, `insert`, `update` and `delete`. All these returns a Statement struct, which you can then modify (with .filter, .limit, .onConflict, .orderBy). The statement is just an immutable struct, no magic going on. You can save it, serialize it, etc. When you want to run the statement, you just call the run method, which takes a database handler to run it in, and might throw an error, or give you a result. The type of the result depends on which initial method created the statement.

### Query DSL

The query DSL supports following operators:

Is equal: `column == value (e.g. Bicycle.id == 1)`

Is not equal: `column != value`

Is less than: `column < value`

Is less than or equal: `column <= value`

Is greater than: `column > value`

Is greater than or equal: `column => value`

And: `expression && expression`

Or: `expression || expression`

Inverse: `!expression`

Is null: `!column`

Contains: `column ∈ [value]` or `contains(column, value)`

String lowercase: `column.lowercase()`

String uppercase: `column.uppercase()`

In-string search: `column.like(value)` (e.g. Bicycle.name.like("%bike%"))

`column` means an instance of a Column struct, e.g. `Bicycle.id`.

`value` means any value that works with SQL, like Int, String, Double, etc.

`expression` is anything returned by one of these operators

## Who made this?

I did. My name is Ulrik Flænø Damm, I’m an iOS and Unity developer at Northplay in Copenhagen. You can [follow me on Twitter](https://twitter.com/ulrikdamm), or visit [my website](https://ufd.dk).

If you want to contribute with code or ideas, open some issues or submit some pull requests!
