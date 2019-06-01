//
//  SqlableTests.swift
//  SqlableTests
//
//  Created by Ulrik Damm on 26/10/2015.
//  Copyright © 2015 Ufd.dk. All rights reserved.
//

import XCTest
@testable import Sqlable

func documentsPath() -> String {
	return NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
}

struct User {
	let id : Int?
	var name : String
	var avatarURL : String?
	var groupId : Int
}

struct Group {
	let id : Int
}

extension Group : Sqlable {
	static let id = Column("id", .integer, PrimaryKey(autoincrement: true))
	static let tableLayout = [id]
	
	init(row : ReadRow) throws {
		id = try row.get(Group.id)
	}
	
	func valueForColumn(_ column : Column) -> SqlValue? {
		switch column {
		case Group.id: return id
		case _: return nil
		}
	}
}

extension User : Sqlable {
	static let id = Column("id", .integer, PrimaryKey(autoincrement: true))
	static let name = Column("name", .text)
	static let avatarURL = Column("avatar_url", .nullable(.text))
	static let groupId = Column("group_id", .integer, ForeignKey<Group>())
	static let tableLayout = [id, name, avatarURL, groupId]
	
	init(row : ReadRow) throws {
		id = try row.get(User.id)
		name = try row.get(User.name)
		avatarURL = try row.get(User.avatarURL)
		groupId = try row.get(User.groupId)
	}
	
	func valueForColumn(_ column : Column) -> SqlValue? {
		switch column {
		case User.id: return id
		case User.name: return name
		case User.avatarURL: return avatarURL ?? Null()
		case User.groupId: return groupId
		case _: return nil
		}
	}
}

class SqliteDatabaseTests: XCTestCase {
	let path = documentsPath() + "/test.sqlite"
	var db : SqliteDatabase!
	
	override func setUp() {
		_ = try? SqliteDatabase.deleteDatabase(at: path)
		db = try! SqliteDatabase(filepath: path)
	}
	
	func testExecute() {
		try! db.execute("create table test (id integer)")
	}
	
	func testCreateTable() {
		try! db.createTable(User.self)
	}
	
	func testInsert() {
		try! db.createTable(User.self)
		try! db.createTable(Group.self)
		
		let group = Group(id: 0)
		let user = User(id: nil, name: "Ulrik", avatarURL: nil, groupId: 0)
		
		try! group.insert().run(db)
		try! user.insert().run(db)
	}
	
	func testDelete() {
		try! db.createTable(User.self)
		try! db.createTable(Group.self)
		
		let group = Group(id: 0)
		let user = User(id: nil, name: "Ulrik", avatarURL: nil, groupId: 0)
		
		try! group.insert().run(db)
		try! user.insert().run(db)
		
		try! User.delete(User.id == 1).run(db)
		try! group.delete().run(db)
	}
	
	func testCount() {
		try! db.createTable(Group.self)
		try! Group(id: 0).insert().run(db)
		try! Group(id: 1).insert().run(db)
		
		let count = try! Group.count().run(db)
		XCTAssert(count == 2)
	}
	
	func testRead() {
		try! db.createTable(User.self)
		try! db.createTable(Group.self)
		
		let group = Group(id: 0)
		let user1 = User(id: nil, name: "Ulrik", avatarURL: nil, groupId: 0)
		let user2 = User(id: nil, name: "Luz", avatarURL: "", groupId: 0)
		
		try! group.insert().run(db)
		try! user1.insert().run(db)
		try! user2.insert().run(db)
		
		let users = try! User.read().run(db)
		XCTAssert(users.count == 2)
		
		XCTAssert(users[0].id == 1)
		XCTAssert(users[0].name == "Ulrik")
		XCTAssert(users[0].avatarURL == nil)
		XCTAssert(users[0].groupId == 0)
		
		XCTAssert(users[1].id == 2)
		XCTAssert(users[1].name == "Luz")
		XCTAssert(users[1].avatarURL == "")
		XCTAssert(users[1].groupId == 0)
	}
	
	func testFilter() {
		try! db.createTable(User.self)
		try! db.createTable(Group.self)
		
		let group = Group(id: 0)
		let user1 = User(id: nil, name: "Ulrik", avatarURL: nil, groupId: 0)
		let user2 = User(id: nil, name: "Luz", avatarURL: "", groupId: 0)
		
		try! group.insert().run(db)
		try! user1.insert().run(db)
		try! user2.insert().run(db)
		
		let users = try! User.read().filter(User.name == "Luz").run(db)
		XCTAssert(users.count == 1)
		
		XCTAssert(users[0].id == 2)
		XCTAssert(users[0].name == "Luz")
		XCTAssert(users[0].avatarURL == "")
		XCTAssert(users[0].groupId == 0)
	}
	
	func testOrder() {
		try! db.createTable(User.self)
		try! db.createTable(Group.self)
		
		let group = Group(id: 0)
		let user1 = User(id: nil, name: "Ulrik", avatarURL: nil, groupId: 0)
		let user2 = User(id: nil, name: "Luz", avatarURL: "", groupId: 0)
		
		try! group.insert().run(db)
		try! user1.insert().run(db)
		try! user2.insert().run(db)
		
		let users = try! User.read().orderBy(User.name).run(db)
		XCTAssert(users.count == 2)
		
		XCTAssert(users[0].id == 2)
		XCTAssert(users[0].name == "Luz")
		XCTAssert(users[0].avatarURL == "")
		XCTAssert(users[0].groupId == 0)
		
		XCTAssert(users[1].id == 1)
		XCTAssert(users[1].name == "Ulrik")
		XCTAssert(users[1].avatarURL == nil)
		XCTAssert(users[1].groupId == 0)
	}
	
	func testLimit() {
		try! db.createTable(User.self)
		try! db.createTable(Group.self)
		
		let group = Group(id: 0)
		let user1 = User(id: nil, name: "Ulrik", avatarURL: nil, groupId: 0)
		let user2 = User(id: nil, name: "Luz", avatarURL: "", groupId: 0)
		
		try! group.insert().run(db)
		try! user1.insert().run(db)
		try! user2.insert().run(db)
		
		let users = try! User.read().orderBy(User.name, .desc).limit(1).run(db)
		XCTAssert(users.count == 1)
		
		XCTAssert(users[0].id == 1)
		XCTAssert(users[0].name == "Ulrik")
		XCTAssert(users[0].avatarURL == nil)
		XCTAssert(users[0].groupId == 0)
	}
	
	func testUpdate() {
		try! db.createTable(User.self)
		try! db.createTable(Group.self)
		
		let group = Group(id: 0)
		var user1 = User(id: 1, name: "Ulrik", avatarURL: nil, groupId: 0)
		let user2 = User(id: 2, name: "Luz", avatarURL: "", groupId: 0)
		
		try! group.insert().run(db)
		try! user1.insert().run(db)
		try! user2.insert().run(db)
		
		user1.avatarURL = "http://"
		try! user1.update().run(db)
		
		let users = try! User.read().orderBy(User.name).run(db)
		XCTAssert(users.count == 2)
		
		XCTAssert(users[0].id == 2)
		XCTAssert(users[0].name == "Luz")
		XCTAssert(users[0].avatarURL == "")
		XCTAssert(users[0].groupId == 0)
		
		XCTAssert(users[1].id == 1)
		XCTAssert(users[1].name == "Ulrik")
		XCTAssert(users[1].avatarURL == "http://")
		XCTAssert(users[1].groupId == 0)
	}
	
	func testLimitedCount() {
		try! db.createTable(User.self)
		try! db.createTable(Group.self)
		
		let group = Group(id: 0)
		let user1 = User(id: nil, name: "Ulrik", avatarURL: nil, groupId: 0)
		let user2 = User(id: nil, name: "Luz", avatarURL: "", groupId: 0)
		
		try! group.insert().run(db)
		try! user1.insert().run(db)
		try! user2.insert().run(db)
		
		let count = try! User.count().filter(User.name == "Luz").run(db)
		XCTAssert(count == 1)
	}
	
	// Regression test for bug found by siuying (https://github.com/ulrikdamm/Sqlable/issues/2)
	func testById() {
		try! db.createTable(Group.self)
		let group = Group(id: 0)
		try! group.insert().run(db)
		
		if let _ = try! Group.byId(1).run(db).value {
			XCTFail("group should not be found")
		} else {
			XCTAssert(true)
		}
	}
}

struct Bicycle {
	let id : Int?
	var name : String
	var color : String
}

extension Bicycle : Sqlable {
	static let id = Column("id", .integer, PrimaryKey(autoincrement: true))
	static let name = Column("name", .text)
	static let color = Column("color", .text)
	static let tableLayout = [id, name, color]
	
	func valueForColumn(_ column : Column) -> SqlValue? {
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
