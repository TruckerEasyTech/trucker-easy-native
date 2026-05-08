import SwiftUI
import PhotosUI
import SwiftData

// MARK: - Community View (inside RoadTalk tab)
struct CommunityView: View {
    @State private var showingNewPost = false
    @State private var selectedCategory: PostCategory?
    @State private var searchText = ""
    @State private var posts: [CommunityPost] = []
    @State private var isLoading = false
    @State private var usingOfflineFallback = false

    var filteredPosts: [CommunityPost] {
        var result = posts
        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }
        if !searchText.isEmpty {
            result = result.filter { post in
                post.title.localizedCaseInsensitiveContains(searchText) ||
                post.content.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    var body: some View {
        ZStack {
            AppTheme.Colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                // Category filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        CommunityChip(title: "All", icon: "square.grid.2x2", isSelected: selectedCategory == nil) {
                            selectedCategory = nil
                        }
                        ForEach(PostCategory.allCases, id: \.self) { cat in
                            CommunityChip(title: cat.rawValue, icon: iconForCategory(cat), isSelected: selectedCategory == cat) {
                                selectedCategory = cat
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)
                }

                Divider().background(AppTheme.Colors.textSecondary.opacity(0.15))

                if isLoading && filteredPosts.isEmpty {
                    VStack {
                        Spacer()
                        ProgressView()
                            .tint(AppTheme.Colors.accent)
                        Spacer()
                    }
                } else if filteredPosts.isEmpty {
                    CommunityEmptyState(onNewPost: { showingNewPost = true })
                } else {
                    ScrollView {
                        LazyVStack(spacing: AppTheme.Spacing.sm) {
                            ForEach(filteredPosts) { post in
                                NavigationLink(destination: PostDetailView(post: post)) {
                                    CommunityPostCard(post: post)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(AppTheme.Spacing.md)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search posts...")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingNewPost = true }) {
                    Image(systemName: "square.and.pencil")
                        .foregroundColor(AppTheme.Colors.accent)
                        .font(.system(size: 18, weight: .semibold))
                }
            }
        }
        .sheet(isPresented: $showingNewPost) {
            NewPostView { post in
                posts.insert(post, at: 0)
            }
                .preferredColorScheme(.dark)
        }
        .task {
            await loadPosts()
        }
        .onChange(of: selectedCategory) { _, _ in
            Task { await loadPosts() }
        }
    }

    private func iconForCategory(_ category: PostCategory) -> String {
        switch category {
        case .general:     return "bubble.left"
        case .advice:      return "lightbulb"
        case .routes:      return "map"
        case .safety:      return "shield"
        case .mechanical:  return "wrench.and.screwdriver"
        case .regulations: return "doc.text"
        case .social:      return "person.3"
        }
    }

    @MainActor
    private func loadPosts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let category = selectedCategory?.rawValue
            let records = try await SupabaseClient.shared.fetchCommunityPosts(category: category)
            posts = records.map(CommunityPost.init(record:))
            usingOfflineFallback = false
        } catch {
            print("CommunityView: failed to load posts — \(error.localizedDescription)")
            posts = []
            usingOfflineFallback = false
        }
    }
}

private enum CommunityFallbackData {
    static func samplePosts(category: PostCategory?) -> [CommunityPost] {
        let seeded: [CommunityPost] = [
            makePost(
                title: "I-40 East truck parking available",
                content: "Loves Travel Stop near exit 126 has around 20 open spots right now.",
                author: "Lucas T.",
                category: .routes,
                location: "I-40 Exit 126"
            ),
            makePost(
                title: "Scale open in Oklahoma",
                content: "Weigh station mile marker 221 is open. Keep paperwork ready.",
                author: "Mia R.",
                category: .regulations,
                location: "I-35 MM 221"
            ),
            makePost(
                title: "Strong crosswind warning",
                content: "Crosswind hits hard on bridge section after mile 90. Reduce speed.",
                author: "David K.",
                category: .safety,
                location: "US-54"
            )
        ]

        guard let category else { return seeded }
        return seeded.filter { $0.category == category }
    }

    private static func makePost(
        title: String,
        content: String,
        author: String,
        category: PostCategory,
        location: String
    ) -> CommunityPost {
        let post = CommunityPost(
            title: title,
            content: content,
            authorId: "offline-\(author)",
            authorName: author,
            category: category,
            location: location
        )
        post.likeCount = Int.random(in: 3...19)
        post.commentCount = Int.random(in: 0...8)
        return post
    }
}

// MARK: - Community Chip
struct CommunityChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .bold : .regular))
            }
            .foregroundColor(isSelected ? AppTheme.Colors.background : AppTheme.Colors.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(isSelected ? AppTheme.Colors.accent : AppTheme.Colors.backgroundCard)
            .cornerRadius(AppTheme.Radius.pill)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.pill)
                    .stroke(isSelected ? AppTheme.Colors.accent : AppTheme.Colors.textSecondary.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

// MARK: - Community Post Card
struct CommunityPostCard: View {
    let post: CommunityPost

    private var categoryColor: Color {
        switch post.category {
        case .safety:      return AppTheme.Colors.danger
        case .routes:      return AppTheme.Colors.accent
        case .advice:      return AppTheme.Colors.ctaGlow
        case .mechanical:  return AppTheme.Colors.warning
        case .regulations: return AppTheme.Colors.accentSoft
        default:           return AppTheme.Colors.textSecondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack(spacing: 10) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.accent.opacity(0.15))
                        .frame(width: 38, height: 38)
                    Text(String(post.authorName.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.Colors.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text(post.createdDate, style: .relative)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                Spacer()
                // Category badge
                Text(post.category.rawValue)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(categoryColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(categoryColor.opacity(0.12))
                    .cornerRadius(AppTheme.Radius.pill)
            }

            // Title
            Text(post.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)

            // Content preview
            Text(post.content)
                .font(AppTheme.Typography.caption())
                .foregroundColor(AppTheme.Colors.textSecondary)
                .lineLimit(2)

            // Post image if any
            if let imageData = post.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 130)
                    .clipped()
                    .cornerRadius(AppTheme.Radius.sm)
            }

            // Footer
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "heart")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.Colors.danger)
                    Text("\(post.likeCount)")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.Colors.accent)
                    Text("\(post.commentCount)")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                if let location = post.location {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                        Text(location)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .stroke(AppTheme.Colors.textSecondary.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Community Empty State
struct CommunityEmptyState: View {
    let onNewPost: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Spacer()
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.accent.opacity(0.08))
                    .frame(width: 100, height: 100)
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 44))
                    .foregroundColor(AppTheme.Colors.accent.opacity(0.5))
            }
            Text("No posts yet")
                .font(AppTheme.Typography.cardTitle())
                .foregroundColor(.white)
            Text("Be the first to share tips, routes or news with fellow drivers!")
                .font(AppTheme.Typography.caption())
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(action: onNewPost) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                    Text("Write First Post")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [AppTheme.Colors.cta, Color(hex: "#E65100")],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(AppTheme.Radius.pill)
                .shadow(color: AppTheme.Colors.cta.opacity(0.5), radius: 10, y: 4)
            }
            Spacer()
        }
    }
}

// MARK: - Post Detail View
struct PostDetailView: View {
    @Bindable var post: CommunityPost
    @State private var comments: [PostComment] = []
    @State private var newComment = ""
    @State private var hasLiked = false
    @State private var isLoadingComments = false

    var postComments: [PostComment] {
        comments.sorted { $0.createdDate > $1.createdDate }
    }

    private var categoryColor: Color {
        switch post.category {
        case .safety:      return AppTheme.Colors.danger
        case .routes:      return AppTheme.Colors.accent
        case .advice:      return AppTheme.Colors.ctaGlow
        case .mechanical:  return AppTheme.Colors.warning
        case .regulations: return AppTheme.Colors.accentSoft
        default:           return AppTheme.Colors.textSecondary
        }
    }

    var body: some View {
        ZStack {
            AppTheme.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Post header card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(AppTheme.Colors.accent.opacity(0.15))
                                    .frame(width: 46, height: 46)
                                Text(String(post.authorName.prefix(1)).uppercased())
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(AppTheme.Colors.accent)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(post.authorName)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                                HStack(spacing: 6) {
                                    Text(post.createdDate, style: .relative)
                                        .font(.system(size: 12))
                                        .foregroundColor(AppTheme.Colors.textSecondary)
                                    if let location = post.location {
                                        Text("•").foregroundColor(AppTheme.Colors.textSecondary).font(.system(size: 12))
                                        Image(systemName: "location.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(AppTheme.Colors.textSecondary)
                                        Text(location)
                                            .font(.system(size: 12))
                                            .foregroundColor(AppTheme.Colors.textSecondary)
                                    }
                                }
                            }
                            Spacer()
                            Text(post.category.rawValue)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(categoryColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(categoryColor.opacity(0.12))
                                .cornerRadius(AppTheme.Radius.pill)
                        }

                        Text(post.title)
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)

                        Text(post.content)
                            .font(AppTheme.Typography.body())
                            .foregroundColor(AppTheme.Colors.textSecondary)

                        if let imageData = post.imageData, let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(AppTheme.Radius.md)
                        }

                        // Action bar
                        HStack(spacing: 20) {
                            Button(action: toggleLike) {
                                HStack(spacing: 6) {
                                    Image(systemName: hasLiked ? "heart.fill" : "heart")
                                        .font(.system(size: 16))
                                        .foregroundColor(hasLiked ? AppTheme.Colors.danger : AppTheme.Colors.textSecondary)
                                    Text("\(post.likeCount)")
                                        .font(.system(size: 13))
                                        .foregroundColor(AppTheme.Colors.textSecondary)
                                }
                            }
                            HStack(spacing: 6) {
                                Image(systemName: "bubble.right")
                                    .font(.system(size: 16))
                                    .foregroundColor(AppTheme.Colors.accent)
                                Text("\(postComments.count)")
                                    .font(.system(size: 13))
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                            }
                            Spacer()
                            Button(action: {}) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 16))
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                            }
                        }
                    }
                    .padding(AppTheme.Spacing.md)
                    .background(AppTheme.Colors.backgroundCard)

                    Divider().background(AppTheme.Colors.textSecondary.opacity(0.1))

                    // Comments section
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text("COMMENTS (\(postComments.count))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .kerning(1.2)
                            .padding(.horizontal, AppTheme.Spacing.md)
                            .padding(.top, AppTheme.Spacing.md)

                        if isLoadingComments && postComments.isEmpty {
                            ProgressView()
                                .tint(AppTheme.Colors.accent)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else if postComments.isEmpty {
                            Text("No comments yet. Be the first!")
                                .font(AppTheme.Typography.caption())
                                .foregroundColor(AppTheme.Colors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            ForEach(postComments) { comment in
                                StyledCommentRow(comment: comment)
                                    .padding(.horizontal, AppTheme.Spacing.md)
                            }
                        }
                    }

                    Spacer(minLength: 80)
                }
            }

            // Floating comment input
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(AppTheme.Colors.accent.opacity(0.15)).frame(width: 36, height: 36)
                        Text("D").font(.system(size: 15, weight: .bold)).foregroundColor(AppTheme.Colors.accent)
                    }
                    TextField("Add a comment...", text: $newComment)
                        .font(AppTheme.Typography.body())
                        .foregroundColor(.white)
                        .padding(10)
                        .background(AppTheme.Colors.backgroundInput)
                        .cornerRadius(AppTheme.Radius.pill)
                    Button(action: addComment) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 18))
                            .foregroundColor(newComment.isEmpty ? AppTheme.Colors.textSecondary : AppTheme.Colors.accent)
                    }
                    .disabled(newComment.isEmpty)
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(AppTheme.Colors.backgroundSecond)
            }
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadComments()
        }
    }

    private func toggleLike() {
        hasLiked.toggle()
        post.likeCount += hasLiked ? 1 : -1
    }

    private func addComment() {
        guard !newComment.isEmpty else { return }
        let content = newComment
        newComment = ""

        Task {
            guard let postID = post.remoteID else {
                await MainActor.run {
                    newComment = content
                }
                return
            }

            do {
                let record = try await SupabaseClient.shared.submitPostComment(
                    PostCommentPayload(
                        post_id: postID,
                        author_id: SupabaseClient.shared.currentDriverId,
                        content: content
                    )
                )
                let comment = PostComment(record: record, localPostId: post.id)
                await MainActor.run {
                    comments.insert(comment, at: 0)
                    post.commentCount = max(post.commentCount, comments.count)
                }
            } catch {
                print("PostDetailView: failed to submit comment — \(error.localizedDescription)")
                await MainActor.run {
                    newComment = content
                }
            }
        }
    }

    @MainActor
    private func loadComments() async {
        guard let postID = post.remoteID else { return }
        isLoadingComments = true
        defer { isLoadingComments = false }

        do {
            let records = try await SupabaseClient.shared.fetchPostComments(postId: postID)
            comments = records.map { PostComment(record: $0, localPostId: post.id) }
            post.commentCount = max(post.commentCount, comments.count)
        } catch {
            print("PostDetailView: failed to load comments — \(error.localizedDescription)")
        }
    }
}

// MARK: - Styled Comment Row
struct StyledCommentRow: View {
    let comment: PostComment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.accent.opacity(0.12))
                    .frame(width: 34, height: 34)
                Text(String(comment.authorName.prefix(1)).uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AppTheme.Colors.accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(comment.authorName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text(comment.createdDate, style: .relative)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                Text(comment.content)
                    .font(AppTheme.Typography.caption())
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
        .padding(10)
        .background(AppTheme.Colors.backgroundInput)
        .cornerRadius(AppTheme.Radius.sm)
    }
}

// MARK: - New Post View
struct NewPostView: View {
    @Environment(\.dismiss) private var dismiss
    let onPostCreated: (CommunityPost) -> Void

    @State private var title = ""
    @State private var content = ""
    @State private var category = PostCategory.general
    @State private var location = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.md) {
                        // Category picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CATEGORY")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                                .kerning(1.2)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(PostCategory.allCases, id: \.self) { cat in
                                        Button(action: { category = cat }) {
                                            Text(cat.rawValue)
                                                .font(.system(size: 13, weight: category == cat ? .bold : .regular))
                                                .foregroundColor(category == cat ? AppTheme.Colors.background : AppTheme.Colors.textSecondary)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 7)
                                                .background(category == cat ? AppTheme.Colors.accent : AppTheme.Colors.backgroundCard)
                                                .cornerRadius(AppTheme.Radius.pill)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)

                        // Title
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TITLE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                                .kerning(1.2)
                            TextField("Post title...", text: $title)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(AppTheme.Colors.backgroundInput)
                                .cornerRadius(AppTheme.Radius.md)
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)

                        // Content
                        VStack(alignment: .leading, spacing: 8) {
                            Text("YOUR MESSAGE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                                .kerning(1.2)
                            ZStack(alignment: .topLeading) {
                                if content.isEmpty {
                                    Text("Share tips, route info, or anything useful for fellow drivers...")
                                        .font(AppTheme.Typography.body())
                                        .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.5))
                                        .padding(14)
                                }
                                TextEditor(text: $content)
                                    .font(AppTheme.Typography.body())
                                    .foregroundColor(.white)
                                    .frame(minHeight: 130)
                                    .padding(8)
                                    .scrollContentBackground(.hidden)
                            }
                            .background(AppTheme.Colors.backgroundInput)
                            .cornerRadius(AppTheme.Radius.md)
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)

                        // Location
                        VStack(alignment: .leading, spacing: 8) {
                            Text("LOCATION (OPTIONAL)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                                .kerning(1.2)
                            HStack {
                                Image(systemName: "location.fill")
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                                TextField("City, State", text: $location)
                                    .font(AppTheme.Typography.body())
                                    .foregroundColor(.white)
                            }
                            .padding(12)
                            .background(AppTheme.Colors.backgroundInput)
                            .cornerRadius(AppTheme.Radius.md)
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)

                        // Photo
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PHOTO (OPTIONAL)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                                .kerning(1.2)
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                if let imageData, let uiImage = UIImage(data: imageData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 160)
                                        .clipped()
                                        .cornerRadius(AppTheme.Radius.md)
                                } else {
                                    HStack {
                                        Image(systemName: "photo.on.rectangle")
                                            .font(.system(size: 20))
                                            .foregroundColor(AppTheme.Colors.textSecondary)
                                        Text("Tap to add a photo")
                                            .font(AppTheme.Typography.body())
                                            .foregroundColor(AppTheme.Colors.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 80)
                                    .background(AppTheme.Colors.backgroundInput)
                                    .cornerRadius(AppTheme.Radius.md)
                                }
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)

                        Spacer(minLength: AppTheme.Spacing.xxl)
                    }
                    .padding(.top, AppTheme.Spacing.md)
                }
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") { savePost() }
                        .foregroundColor(AppTheme.Colors.accent)
                        .fontWeight(.bold)
                        .disabled(title.isEmpty || content.isEmpty || isSubmitting)
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self) {
                        imageData = data
                    }
                }
            }
        }
    }

    private func savePost() {
        isSubmitting = true
        Task {
            let payload = CommunityPostPayload(
                author_id: SupabaseClient.shared.currentDriverId,
                title: title,
                content: content,
                category: category.rawValue,
                location: location.isEmpty ? nil : location
            )
            do {
                let record = try await SupabaseClient.shared.submitCommunityPost(payload)
                let post = CommunityPost(record: record)
                post.imageData = imageData
                await MainActor.run {
                    onPostCreated(post)
                    dismiss()
                }
            } catch {
                print("NewPostView: failed to submit post — \(error.localizedDescription)")
            }
            await MainActor.run {
                isSubmitting = false
            }
        }
    }
}

private extension CommunityPost {
    convenience init(record: CommunityPostRecord) {
        self.init(
            title: record.title,
            content: record.content,
            authorId: record.author_id ?? record.id,
            authorName: "Driver",
            category: PostCategory(rawValue: record.category ?? "") ?? .general,
            remoteID: record.id,
            location: record.location
        )
        if let createdAt = ISO8601DateFormatter().date(from: record.created_at) {
            createdDate = createdAt
        }
        likeCount = record.like_count ?? 0
        commentCount = record.comment_count ?? 0
    }
}

private extension PostComment {
    convenience init(record: PostCommentRecord, localPostId: UUID) {
        self.init(
            postId: localPostId,
            content: record.content,
            authorId: record.author_id ?? record.id,
            authorName: "Driver",
            remoteID: record.id
        )
        if let createdAt = ISO8601DateFormatter().date(from: record.created_at) {
            createdDate = createdAt
        }
    }
}

#Preview {
    NavigationStack {
        CommunityView()
    }
    .modelContainer(for: [CommunityPost.self, PostComment.self], inMemory: true)
    .preferredColorScheme(.dark)
}
