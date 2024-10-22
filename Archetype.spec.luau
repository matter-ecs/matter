local Archetype = require(script.Parent.Archetype)
local component = require(script.Parent).component

return function()
	describe("archetype", function()
		it("should report same sets as same archetype", function()
			local a = component()
			local b = component()
			expect(Archetype.hash({ #a, #b })).to.equal(Archetype.hash({ #b, #a }))
		end)
	end)
end
