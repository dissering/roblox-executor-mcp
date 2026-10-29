return function(context, Bridge)
local MarketplaceService = context.MarketplaceService
local RobloxReplicatedStorage = context.RobloxReplicatedStorage

    Bridge:BindToType("search-instances", function(data)
        local rootInstance = loadstring("return " .. data.root)()
        local instances = rootInstance:QueryDescendants(data.selector)
        
        local limit = math.max(1, math.min(tonumber(data.limit) or 20, 100))
        local results = {}
        
        for i, instance in instances do
            if i > limit then break end

            local fullName = instance.Name
            pcall(function() fullName = instance:GetFullName() end)

            table.insert(results, {
                Name = instance.Name,
                ClassName = instance.ClassName,
                Path = fullName,
                DebugId = instance:GetDebugId()
            })
        end
        
        return {
            count = #instances,
            limited = #instances > limit,
            results = results
        }
    end)

    Bridge:BindToType("get-game-info", function(data)
        local productOk, productInfo = pcall(function() return MarketplaceService:GetProductInfo(game.PlaceId) end)
        if not productOk or type(productInfo) ~= "table" then productInfo = {} end
        local creator = productInfo.Creator or {}
        local serverType = "Unknown"
        pcall(function() serverType = RobloxReplicatedStorage.GetServerType:InvokeServer() end)

        local info = {
            PlaceId = game.PlaceId,
            GameId = game.GameId,
            PlaceVersion = game.PlaceVersion,
            PlaceName = productInfo.Name,
            Creator = creator.Name,
            CreatorType = creator.CreatorType and tostring(creator.CreatorType) or nil,
            CreatorId = creator.CreatorTargetId,
            JobId = game.JobId,
            ServerType = serverType,
            Executor = context.Compatibility.Info,
        }

        -- The marketplace description can be multi-kB of marketing text that is
        -- pure noise for debugging, so omit it unless explicitly requested.
        if data.includeDescription == true then
            info.PlaceDescription = productInfo.Description
        end

        return info
    end)

    Bridge:BindToType("get-descendants-tree", function(data)
        local rootInstance = loadstring("return " .. data.root)()
        assert(typeof(rootInstance) == "Instance", "Root path did not resolve to a valid Instance.")

        local maxDepth = math.max(0, math.min(tonumber(data.maxDepth) or 2, 5))
        local maxChildren = math.max(1, math.min(tonumber(data.maxChildren) or 20, 30))
        local classFilter = data.classFilter or ""
        local hasFilter = classFilter ~= ""
        local summaryOnly = data.summaryOnly == true
        local MAX_TREE_NODES = 300
        local nodeBudget = MAX_TREE_NODES
        local budgetHit = false

        if summaryOnly then
            local classCounts = {}
            local visited = 0
            local matched = 0

            local function walk(instance, depth)
                if depth > maxDepth then
                    return
                end

                for _, child in instance:GetChildren() do
                    visited += 1
                    if not hasFilter or child:IsA(classFilter) then
                        matched += 1
                        classCounts[child.ClassName] = (classCounts[child.ClassName] or 0) + 1
                    end
                    if depth < maxDepth then
                        walk(child, depth + 1)
                    end
                end
            end

            walk(rootInstance, 1)

            return {
                Root = {
                    Name = rootInstance.Name,
                    ClassName = rootInstance.ClassName,
                    ChildCount = #rootInstance:GetChildren(),
                },
                MaxDepth = maxDepth,
                ClassFilter = if hasFilter then classFilter else nil,
                VisitedDescendants = visited,
                MatchedDescendants = matched,
                ClassCounts = classCounts,
            }
        end

        local function buildTree(instance, depth)
            if depth > maxDepth then
                return nil
            end

            local children = instance:GetChildren()
            local childNodes = {}
            local shown = 0
            local total = #children

            for _, child in children do
                if shown >= maxChildren then break end
                if nodeBudget <= 0 then
                    budgetHit = true
                    break
                end

                if hasFilter and not child:IsA(classFilter) then
                    -- Even if this child doesn't match, check if any descendant might
                    -- Only skip if we're at max depth anyway
                    if depth < maxDepth then
                        local subtree = buildTree(child, depth + 1)
                        if subtree and subtree.Children and #subtree.Children > 0 then
                            table.insert(childNodes, subtree)
                            shown += 1
                        end
                    end
                    continue
                end

                nodeBudget -= 1

                local node = {
                    Name = child.Name,
                    ClassName = child.ClassName,
                    ChildCount = #child:GetChildren()
                }

                if depth < maxDepth and node.ChildCount > 0 then
                    local subtree = buildTree(child, depth + 1)
                    if subtree then
                        node.Children = subtree.Children
                    end
                end

                table.insert(childNodes, node)
                shown += 1
            end

            return {
                Name = instance.Name,
                ClassName = instance.ClassName,
                ChildCount = total,
                TruncatedAt = if shown < total then shown else nil,
                Children = childNodes
            }
        end

        local tree = buildTree(rootInstance, 0)
        if budgetHit and typeof(tree) == "table" then
            tree.Note = "Output capped at " .. MAX_TREE_NODES .. " nodes. Narrow with classFilter, lower maxDepth, or summaryOnly=true."
        end
        return tree
    end)
end
