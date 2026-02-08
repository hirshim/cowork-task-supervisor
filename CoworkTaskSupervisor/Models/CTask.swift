import Foundation
import SwiftData

@Model
final class CTask {
  var id: UUID
  var title: String?
  var prompt: String
  var comment: String?
  var status: TaskStatus
  var category: String?
  var order: Int
  var response: String?
  var errorMessage: String?
  var createdAt: Date
  var updatedAt: Date
  var executedAt: Date?

  init(
    title: String? = nil,
    prompt: String,
    comment: String? = nil,
    category: String? = nil,
    order: Int = 0
  ) {
    self.id = UUID();
    self.title = title;
    self.prompt = prompt;
    self.comment = comment;
    self.status = .pending;
    self.category = category;
    self.order = order;
    self.response = nil;
    self.errorMessage = nil;
    self.createdAt = Date();
    self.updatedAt = Date();
    self.executedAt = nil;
  }
}
