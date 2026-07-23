package ui.contextmenu;

import openfl.display.Sprite;
import ui.contextmenu.data.MenuCategory;

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     CATEGORY SIDEBAR                                      ║
 * ║          (Left panel with category buttons)                               ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Left panel of the context menu containing category buttons.              ║
 * ║Categories are displayed vertically in order.                              ║
 * ║                                                                           ║
 * ║  Architecture:                                                            ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  CategorySidebar (Sprite)                                           │  ║
 * ║  │                                                                     │  ║
 * ║  │  ┌───────────────────────────────────────────────────────────────┐  │  ║
 * ║  │  │  Visual:                                                      │  │  ║
 * ║  │  │  ┌─────────────────────────────────────────────────────────┐  │  │  ║
 * ║  │  │  │  [Recent]                                               │  │  │  ║
 * ║  │  │  │  [Editor]  ← Selected (blue bg + green accent)          │  │  │  ║
 * ║  │  │  │  [Atoms]                                                │  │  │  ║
 * ║  │  │  │  [Assemblies]                                           │  │  │  ║
 * ║  │  │  └─────────────────────────────────────────────────────────┘  │  │  ║
 * ║  │  │                                                               │  │  ║
 * ║  │  │  Width: 150px (fixed)                                         │  │  ║
 * ║  │  │  Height: Auto (based on category count × 40px)                │  │  ║
 * ║  │  └───────────────────────────────────────────────────────────────┘  │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class CategorySidebar extends Sprite
{
	/** Callback when a category is selected. */
	public var onCategorySelected:MenuCategory -> Void;

	/** Array of category items. */
	private var _items:Array<CategoryItem>;

	/** Currently selected category. */
	private var _selectedCategory:MenuCategory;

	/** Fixed width. */
	private static inline var SIDEBAR_WIDTH:Float = 150.0;

	/**
	 * Create a new category sidebar.
	 *
	 * @param categories Array of categories to display
	 */
	public function new(categories:Array<MenuCategory>)
	{
		super();
		_items = [];
		buildUI(categories);
	}

	/**
	 * Build the sidebar UI with category buttons.
	 *
	 * @param categories Array of categories to display
	 */
	private function buildUI(categories:Array<MenuCategory>):Void
	{
		// Sort categories by order field
		categories.sort(function(a, b) return a.order - b.order);

		var yPos:Float = 0;
		for (category in categories)
		{
			var item = new CategoryItem(category);
			item.y = yPos;
			item.onClick = onCategoryClick;
			addChild(item);
			_items.push(item);
			yPos += item.getItemHeight();
		}

		// Draw background
		graphics.beginFill(0x1a1a24);
		graphics.drawRect(0, 0, SIDEBAR_WIDTH, yPos);
		graphics.endFill();

		// Border line position depends on sidebar position
		// Will be set by setBorderSide() after buildUI()
		_totalHeight = yPos;
		drawBorder(_borderSide);
	}

	/** Current border side. */
	private var _borderSide:SidebarPosition = SidebarPosition.LEFT;

	/** Total height of sidebar content. */
	private var _totalHeight:Float = 0;

	/**
	 * Set which side the border line should appear on.
	 * Called by ContextMenu when sidebar position changes.
	 *
	 * @param side Which side the border should be on
	 */
	public function setBorderSide(side:SidebarPosition):Void
	{
		_borderSide = side;
		if (_totalHeight > 0)
		{
			drawBorder(side);
		}
	}

	/**
	 * Draw border line on specified side.
	 *
	 * @param side Which side to draw border on
	 */
	private function drawBorder(side:SidebarPosition):Void
	{
		// Clear only the border line (redraw background first)
		graphics.beginFill(0x1a1a24);
		graphics.drawRect(0, 0, SIDEBAR_WIDTH, _totalHeight);
		graphics.endFill();

		// Draw border line
		graphics.lineStyle(1, 0x333344);
		switch (side)
		{
			case SidebarPosition.LEFT:
				// Border on right side (sidebar is on left, content on right)
				graphics.moveTo(SIDEBAR_WIDTH, 0);
				graphics.lineTo(SIDEBAR_WIDTH, _totalHeight);
			case SidebarPosition.RIGHT:
				// Border on left side (content is on left, sidebar on right)
				graphics.moveTo(0, 0);
				graphics.lineTo(0, _totalHeight);
		}
	}

	/**
	 * Handle category click.
	 *
	 * @param category Clicked category
	 */
	private function onCategoryClick(category:MenuCategory):Void
	{
		// Deselect previous
		if (_selectedCategory != null)
		{
			for (item in _items)
			{
				if (item.category.id == _selectedCategory.id)
				{
					item.setSelected(false);
					break;
				}
			}
		}

		// Select new
		_selectedCategory = category;
		for (item in _items)
		{
			if (item.category.id == category.id)
			{
				item.setSelected(true);
				break;
			}
		}

		// Notify
		if (onCategorySelected != null)
		{
			onCategorySelected(category);
		}
	}

	/**
	 * Programmatically select a category by ID (without triggering callback).
	 * Used to highlight the preferred category when menu opens.
	 *
	 * @param categoryId Category ID to highlight
	 */
	public function highlightCategory(categoryId:String):Void
	{
		// Deselect all first
		for (item in _items)
		{
			item.setSelected(false);
		}

		// Highlight the requested category
		for (item in _items)
		{
			if (item.category.id == categoryId)
			{
				item.setSelected(true);
				_selectedCategory = item.category;
				break;
			}
		}
	}

	/**
	 * Get sidebar width.
	 */
	public function getSidebarWidth():Float { return SIDEBAR_WIDTH; }

	/**
	 * Get sidebar height.
	 */
	public function getSidebarHeight():Float { return height; }

	/**
	 * Cleanup.
	 */
	public function dispose():Void
	{
		_items = [];
		_selectedCategory = null;
		onCategorySelected = null;
	}
}