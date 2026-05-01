# EncloseHorse Sprite Guide

## Canvas Setup in Procreate

- **Canvas size**: 120×120px (3x retina)
- **Background**: transparent (no background layer)
- **Export**: PNG, no background

For tile backgrounds (grass, water) you can do 120×120 solid/textured fills.
For characters and items, draw centered with some padding — roughly fitting within an 80×80 area inside the 120×120 canvas.

---

## What to Draw

7 sprites per animal. 12 animals = 84 total but do one animal at a time.

| Sprite | Description | Xcode asset name |
|---|---|---|
| animal | The main character (big, centered) | `sprite_[id]_animal` |
| grass | Background tile texture/color | `sprite_[id]_grass` |
| water | Impassable tile | `sprite_[id]_water` |
| wall | Placed wall piece | `sprite_[id]_wall` |
| bonus | Cherry equivalent (+3) | `sprite_[id]_bonus` |
| hazard | Bee equivalent (-5) | `sprite_[id]_hazard` |
| gem | Golden apple equivalent (+10) | `sprite_[id]_gem` |

Replace `[id]` with the animal's id from the list below.

---

## Animal List & Themes

### A Tier
| ID | Name | Suggested theme |
|---|---|---|
| `horse` | Horse | Green fields, wood fence walls, apples, wasps, golden apple |
| `dog` | Dog | Park grass, brick walls, bones, angry cats, golden bone |
| `cat` | Cat | Carpet, yarn walls, fish, dogs, golden fish |
| `rabbit` | Rabbit | Garden, hedge walls, carrots, foxes, golden carrot |
| `bear` | Bear | Forest floor, log walls, honey, bees, golden honeycomb |

### S Tier
| ID | Name | Suggested theme |
|---|---|---|
| `penguin` | Penguin | Ice/snow, iceberg walls, fish, seals, blue diamond |
| `fox` | Fox | Autumn leaves, stick walls, grapes, wolves, crystal |
| `capybara` | Capybara | Muddy ground, reed walls, plants, caimans, lotus |
| `axolotl` | Axolotl | Underwater, coral walls, shrimp, jellyfish, pearl |

### SS Tier
| ID | Name | Suggested theme |
|---|---|---|
| `dragon` | Dragon | Lava/rock, flame walls, gold coins, skulls, crown |
| `unicorn` | Unicorn | Rainbow clouds, star walls, candy, lightning, magic gem |
| `goldhorse` | Golden Horse | Gold tiles, trophy walls, coins, traps, giant gem |

---

## Procreate Tips

- Use a **limited palette** (4-6 colors per animal) — looks more cohesive at small sizes
- Add a **1-2px dark outline** around characters so they pop against the tile background
- The animal sprite is the most important one — spend the most time there
- Grass/water/wall can be simple flat colors or subtle textures, no need to be complex
- Draw all 7 sprites for one animal before moving to the next so the style stays consistent

---

## Adding to Xcode

1. Open `Assets.xcassets` in Xcode
2. Right click → **New Image Set**
3. Name it exactly as shown in the table above e.g. `sprite_penguin_animal`
4. Drag your PNG into the **3x** slot (leave 1x and 2x empty, iOS will scale down)
5. Repeat for each sprite

Once an asset exists, `SpriteView` automatically uses it instead of the emoji fallback — no code changes needed.

---

## Order to Draw (recommended)

1. `horse` — baseline style, everything else should feel consistent with this
2. `penguin` — most different theme, good test of the system
3. `dragon` — SS tier, should feel noticeably more special
4. Fill in the rest

---

## Quick Reference — Asset Names

```
sprite_horse_animal      sprite_horse_grass      sprite_horse_water
sprite_horse_wall        sprite_horse_bonus      sprite_horse_hazard
sprite_horse_gem

sprite_dog_animal        sprite_dog_grass        sprite_dog_water
sprite_dog_wall          sprite_dog_bonus        sprite_dog_hazard
sprite_dog_gem

sprite_cat_animal        sprite_cat_grass        sprite_cat_water
sprite_cat_wall          sprite_cat_bonus        sprite_cat_hazard
sprite_cat_gem

sprite_rabbit_animal     sprite_rabbit_grass     sprite_rabbit_water
sprite_rabbit_wall       sprite_rabbit_bonus     sprite_rabbit_hazard
sprite_rabbit_gem

sprite_bear_animal       sprite_bear_grass       sprite_bear_water
sprite_bear_wall         sprite_bear_bonus       sprite_bear_hazard
sprite_bear_gem

sprite_penguin_animal    sprite_penguin_grass    sprite_penguin_water
sprite_penguin_wall      sprite_penguin_bonus    sprite_penguin_hazard
sprite_penguin_gem

sprite_fox_animal        sprite_fox_grass        sprite_fox_water
sprite_fox_wall          sprite_fox_bonus        sprite_fox_hazard
sprite_fox_gem

sprite_capybara_animal   sprite_capybara_grass   sprite_capybara_water
sprite_capybara_wall     sprite_capybara_bonus   sprite_capybara_hazard
sprite_capybara_gem

sprite_axolotl_animal    sprite_axolotl_grass    sprite_axolotl_water
sprite_axolotl_wall      sprite_axolotl_bonus    sprite_axolotl_hazard
sprite_axolotl_gem

sprite_dragon_animal     sprite_dragon_grass     sprite_dragon_water
sprite_dragon_wall       sprite_dragon_bonus     sprite_dragon_hazard
sprite_dragon_gem

sprite_unicorn_animal    sprite_unicorn_grass    sprite_unicorn_water
sprite_unicorn_wall      sprite_unicorn_bonus    sprite_unicorn_hazard
sprite_unicorn_gem

sprite_goldhorse_animal  sprite_goldhorse_grass  sprite_goldhorse_water
sprite_goldhorse_wall    sprite_goldhorse_bonus  sprite_goldhorse_hazard
sprite_goldhorse_gem
```
