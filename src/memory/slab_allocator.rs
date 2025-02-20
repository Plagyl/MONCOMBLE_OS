/// Taille d'une "page" fictive.
const PAGE_SIZE: usize = 4096;

/// Les tailles de caches que l'on supporte.
const CACHE_SIZES: &[usize] = &[8, 16, 32, 64, 128, 256, 512, 1024, 2048];

/// Nombre maximum de slabs stockés dans un cache.
const MAX_SLABS_PER_CACHE: usize = 16;

/// Nombre maximum d'objets par slab (pour le plus petit object_size = 8).
/// 4096 / 8 = 512 -> on fixe 512 booléens max dans le bitmap.
const MAX_OBJECTS_PER_SLAB: usize = 512;

/// L'allocateur global "SlabAllocator".
pub struct SlabAllocator {
    /// Bump pointer (on avance de page en page)
    heap_start: usize,
    heap_end:   usize,
    bump_ptr:   usize,

    /// Tableau de caches (un par taille possible)
    caches: [SlabCache; CACHE_SIZES.len()],
}

/// Chaque cache gère des slabs pour une taille d'objet donnée.
///
/// On dérive `Clone, Copy` pour pouvoir faire `[SlabCache::empty(); N]`.
#[derive(Clone, Copy)]
pub struct SlabCache {
    /// Taille d'objet (8, 16, 32, ...)
    object_size: usize,

    /// Liste fixe de slabs (Option<Slab>) pour éviter `Vec`.
    ///
    /// Option<Slab> => Slab doit aussi implémenter Copy.
    slabs: [Option<Slab>; MAX_SLABS_PER_CACHE],
}

/// Représente un slab : une page découpée en multiples objets de taille `object_size`.
///
/// On dérive `Clone, Copy` pour le stocker dans `Option<Slab>` au sein d'un tableau.
#[derive(Clone, Copy)]
pub struct Slab {
    start_addr:  usize,
    capacity:    usize,
    used:        usize,
    object_size: usize,

    /// Bitmap : pour chaque index 0..capacity, indique s'il est occupé (true) ou libre (false).
    bitmap: [bool; MAX_OBJECTS_PER_SLAB],
}

impl SlabAllocator {
    /// Constructeur constant "vide".
    pub const fn new() -> Self {
        SlabAllocator {
            heap_start: 0,
            heap_end:   0,
            bump_ptr:   0,
            caches: [SlabCache::empty(); CACHE_SIZES.len()],
        }
    }

    /// Initialisation principale de l'allocateur
    pub unsafe fn init(&mut self, start: usize, size: usize) {
        self.heap_start = start;
        self.heap_end   = start + size;
        self.bump_ptr   = start;

        // On configure chaque cache avec la bonne taille d'objet
        for (i, &sz) in CACHE_SIZES.iter().enumerate() {
            self.caches[i].init(sz);
        }
    }

    /// Alloue `size` octets
    pub unsafe fn allocate(&mut self, size: usize) -> Option<*mut u8> {
        // 1) Trouver l'index du cache qui convient
        let idx = self.find_slab_cache_index(size)?;

        // 2) Effectuer l'allocation dans ce cache, en passant les infos nécessaires.
        let ptr_u8_opt = self.caches[idx].allocate_object(&mut self.bump_ptr, self.heap_end);

        ptr_u8_opt.map(|addr| addr as *mut u8)
    }

    /// Libère un bloc pointé par `ptr`.
    pub unsafe fn deallocate(&mut self, ptr: *mut u8) {
        let addr = ptr as usize;
        // On parcourt tous les caches
        for cache in self.caches.iter_mut() {
            // On parcourt tous les slabs
            for slab_opt in cache.slabs.iter_mut() {
                if let Some(mut slab) = *slab_opt {
                    let start = slab.start_addr;
                    let end   = slab.start_addr + slab.capacity * slab.object_size;

                    if addr >= start && addr < end {
                        // On a trouvé le slab concerné
                        let offset = addr - start;
                        let index  = offset / slab.object_size;
                        if index < slab.capacity && slab.bitmap[index] {
                            // Marque comme libre
                            slab.bitmap[index] = false;
                            slab.used -= 1;
                            // On "réécrit" le slab modifié dans l'Option
                            *slab_opt = Some(slab);
                        }
                        return;
                    }
                }
            }
        }
    }

    /// Trouve l'index du SlabCache qui convient à `size`.
    fn find_slab_cache_index(&self, size: usize) -> Option<usize> {
        for (i, &sz) in CACHE_SIZES.iter().enumerate() {
            if sz >= size {
                return Some(i);
            }
        }
        None
    }
}

impl SlabCache {
    /// Constructeur "vide" pour init statique d'un tableau
    pub const fn empty() -> Self {
        SlabCache {
            object_size: 0,
            slabs: [None; MAX_SLABS_PER_CACHE],
        }
    }

    /// Initialise le cache pour un object_size donné
    pub fn init(&mut self, object_size: usize) {
        self.object_size = object_size;
        // On remet tout à None (c'était déjà None)
        for slot in self.slabs.iter_mut() {
            *slot = None;
        }
    }

    /// Tente d'allouer un objet dans un Slab existant.
    /// Sinon, si tous pleins, on crée un nouveau Slab (1 page) et on y alloue un objet.
    ///
    /// On renvoie Some(addr) si OK, None si échec.
    pub fn allocate_object(
        &mut self,
        bump_ptr: &mut usize,
        heap_end: usize,
    ) -> Option<usize> {
        // 1) Chercher un Slab non plein
        for slab_opt in self.slabs.iter_mut() {
            if let Some(mut slab) = *slab_opt {
                if slab.used < slab.capacity {
                    if let Some(addr) = slab.alloc() {
                        // Mise à jour dans l'Option
                        *slab_opt = Some(slab);
                        return Some(addr);
                    }
                }
            }
        }

        // 2) Sinon, on essaie de créer un nouveau Slab s'il reste de la place dans slabs[]
        for slab_opt in self.slabs.iter_mut() {
            if slab_opt.is_none() {
                // Créer un nouveau slab
                let slab_start = Self::alloc_slab_page(bump_ptr, heap_end)?;
                let mut new_slab = Slab::new(slab_start, PAGE_SIZE, self.object_size)?;
                let addr = new_slab.alloc()?;
                *slab_opt = Some(new_slab);
                return Some(addr);
            }
        }

        // 3) Plus de place pour un nouveau slab => échec
        None
    }

    /// Bump allocate une page de PAGE_SIZE
    fn alloc_slab_page(bump_ptr: &mut usize, heap_end: usize) -> Option<usize> {
        let start = *bump_ptr;
        let end   = start.checked_add(PAGE_SIZE)?;
        if end > heap_end {
            return None;
        }
        *bump_ptr = end;
        Some(start)
    }
}

impl Slab {
    /// Crée un nouveau slab. On vérifie que la taille permet d'avoir au moins 1 objet.
    pub fn new(start_addr: usize, page_size: usize, object_size: usize) -> Option<Self> {
        if object_size == 0 {
            return None;
        }
        let capacity = page_size / object_size;
        if capacity == 0 || capacity > MAX_OBJECTS_PER_SLAB {
            // Soit c'est trop petit pour contenir 1 bloc,
            // soit ça dépasse la taille max de notre bitmap fixe.
            return None;
        }

        Some(Slab {
            start_addr,
            capacity,
            used: 0,
            object_size,
            bitmap: [false; MAX_OBJECTS_PER_SLAB],
        })
    }

    /// Alloue un objet dans ce slab (cherche le premier index libre).
    pub fn alloc(&mut self) -> Option<usize> {
        for i in 0..self.capacity {
            if !self.bitmap[i] {
                // Occupe ce bloc
                self.bitmap[i] = true;
                self.used += 1;
                let addr = self.start_addr + i * self.object_size;
                return Some(addr);
            }
        }
        None
    }
}

